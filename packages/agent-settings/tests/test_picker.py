import asyncio

import pytest
from textual.widgets import Input, OptionList

from agent_settings.picker import DELETE, FORK, SWITCH, Picker, TextPrompt


def test_search_and_select() -> None:
    async def check() -> None:
        app = Picker(["one/model", "two/model"], "codex · default", manage=True)
        async with app.run_test() as pilot:
            await pilot.click(Input)
            await pilot.press("t", "w", "o")
            assert app.query_one(OptionList).option_count == 1
            await pilot.press("enter")
        assert app.return_value == "two/model"

    asyncio.run(check())


@pytest.mark.parametrize("key, action", [("ctrl+n", FORK), ("ctrl+s", SWITCH), ("ctrl+d", DELETE)])
def test_actions_remain_available_during_search(key: str, action: str) -> None:
    async def check() -> None:
        app = Picker(["model"], "claude · default", manage=True)
        async with app.run_test() as pilot:
            await pilot.press("z", key)
        assert app.return_value == action

    asyncio.run(check())


def test_cancel_text_prompt() -> None:
    async def check() -> None:
        app = TextPrompt("Name")
        async with app.run_test() as pilot:
            await pilot.press("escape")
        assert app.return_value is None

    asyncio.run(check())
