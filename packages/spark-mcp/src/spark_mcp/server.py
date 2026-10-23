"""Forward the email-reading subset of `spark mcp` over Streamable HTTP."""

import argparse
import contextlib
import hmac
import shutil
from collections.abc import AsyncGenerator
from importlib.metadata import version
from pathlib import Path

import anyio
import uvicorn
from mcp import ClientSession, McpError, StdioServerParameters, types
from mcp.client.stdio import stdio_client
from mcp.server.fastmcp.server import StreamableHTTPASGIApp
from mcp.server.lowlevel import Server
from mcp.server.streamable_http_manager import StreamableHTTPSessionManager
from starlette.applications import Starlette
from starlette.datastructures import Headers
from starlette.middleware import Middleware
from starlette.responses import PlainTextResponse
from starlette.routing import Route
from starlette.types import ASGIApp, Receive, Scope, Send

# The symlink Spark Desktop installs for its CLI. Run by its real path inside
# the app bundle, the same binary cannot reach the app. /usr/local/bin is not
# on a launchd agent's PATH, so the default is absolute.
SPARK = "/usr/local/bin/spark"

# Spark's server also offers calendar, meeting, team, template, draft, and
# triage tools. This server is reachable from the internet, so it offers only
# what reading mail needs, all of which works on Spark's free plan.
TOOLS = frozenset(
    {"accounts", "folders", "emails", "search", "thread", "attachment", "contacts", "contact"}
)

# Replaces Spark's own instructions, which describe the tools left out above.
INSTRUCTIONS = """\
Read-only access to the user's email through the Spark email client. Call \
`accounts` first to learn the account addresses.

To answer a question about what emails say, use `search` with a topic; it \
returns up to 20 emails with full bodies. Without Spark's AI Assistant the \
topic match is keyword-only and unranked, so search for words the email \
would contain. To find emails by sender, date, or other metadata across every \
folder, use `search` with only a `filter`. Use `emails` to browse the Unified \
Inbox or one folder, `thread` to read a whole conversation, `attachment` to \
fetch a file listed in a thread, and `contacts` to turn a name into an \
address for `from:` and `to:` filters."""

# A call stuck on Spark Desktop would otherwise hold its `spark mcp` process
# open indefinitely.
TIMEOUT_SECONDS = 120


async def forward[ResultT: types.Result](
    spark: str,
    request: types.ListToolsRequest | types.CallToolRequest,
    result_type: type[ResultT],
) -> ResultT:
    # One process per request: it starts in milliseconds and holds no state,
    # so nothing has to outlive a request or survive a restart.
    params = StdioServerParameters(command=spark, args=["mcp"])
    try:
        with anyio.fail_after(TIMEOUT_SECONDS):
            async with (
                stdio_client(params) as (read, write),
                ClientSession(read, write) as session,
            ):
                await session.initialize()
                return await session.send_request(types.ClientRequest(request), result_type)
    except TimeoutError:
        message = f"Spark did not answer within {TIMEOUT_SECONDS} seconds"
        raise McpError(types.ErrorData(code=types.INTERNAL_ERROR, message=message)) from None
    except ExceptionGroup as group:
        # The session's task groups wrap the failure, and the client would
        # see only their generic message.
        error: BaseException = group
        while isinstance(error, BaseExceptionGroup) and len(error.exceptions) == 1:
            error = error.exceptions[0]
        raise error from None


def build_server(spark: str) -> Server:
    server: Server = Server("spark", version=version("spark-mcp"), instructions=INSTRUCTIONS)

    # Requests are rebuilt from their params because the incoming ones keep
    # the client's JSON-RPC envelope (`jsonrpc`, `id`) as extra fields.
    async def list_tools(request: types.ListToolsRequest) -> types.ServerResult:
        upstream = types.ListToolsRequest(params=request.params)
        result = await forward(spark, upstream, types.ListToolsResult)
        result.tools = [tool for tool in result.tools if tool.name in TOOLS]
        return types.ServerResult(result)

    async def call_tool(request: types.CallToolRequest) -> types.ServerResult:
        if request.params.name not in TOOLS:
            message = f"Unknown tool: {request.params.name}"
            raise McpError(types.ErrorData(code=types.INVALID_PARAMS, message=message))
        upstream = types.CallToolRequest(params=request.params)
        return types.ServerResult(await forward(spark, upstream, types.CallToolResult))

    # Registered directly rather than through the decorators, which validate
    # arguments and results against a tool list and would fetch it from Spark
    # a second time. Spark validates its own arguments.
    server.request_handlers[types.ListToolsRequest] = list_tools
    server.request_handlers[types.CallToolRequest] = call_tool
    return server


class RequireToken:
    def __init__(self, app: ASGIApp, token: str) -> None:
        self.app: ASGIApp = app
        self.expected: bytes = f"Bearer {token}".encode()

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] == "http":
            given = Headers(scope=scope).get("authorization", "").encode()
            if not hmac.compare_digest(given, self.expected):
                response = PlainTextResponse(
                    "Unauthorized", status_code=401, headers={"WWW-Authenticate": "Bearer"}
                )
                await response(scope, receive, send)
                return
        await self.app(scope, receive, send)


def build_app(spark: str, token: str) -> Starlette:
    manager = StreamableHTTPSessionManager(build_server(spark), json_response=True, stateless=True)

    @contextlib.asynccontextmanager
    async def lifespan(_: Starlette) -> AsyncGenerator[None]:
        async with manager.run():
            yield

    # Stateless sessions have nothing to send on a GET stream or end with a
    # DELETE, and the transport would hold a GET open until the client gives
    # up. The spec lets a server answer both with 405 instead.
    endpoint = StreamableHTTPASGIApp(manager)
    return Starlette(
        routes=[Route("/mcp", endpoint=endpoint, methods=["POST"])],
        middleware=[Middleware(RequireToken, token=token)],
        lifespan=lifespan,
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="spark-mcp",
        description="Serve Spark's email search and reading tools over MCP at /mcp.",
    )
    parser.add_argument(
        "--token-file",
        type=Path,
        required=True,
        help="file holding the bearer token clients must send",
    )
    parser.add_argument("--host", default="127.0.0.1", help="address to listen on (%(default)s)")
    parser.add_argument("--port", type=int, default=8765, help="port to listen on (%(default)s)")
    parser.add_argument("--spark", default=SPARK, help="Spark CLI executable (%(default)s)")
    args = parser.parse_args()

    token = args.token_file.read_text().strip()
    if not token:
        parser.error(f"{args.token_file} is empty")
    if shutil.which(args.spark) is None:
        parser.error(f"{args.spark} is not an executable; point --spark at the Spark CLI")

    uvicorn.run(build_app(args.spark, token), host=args.host, port=args.port)
