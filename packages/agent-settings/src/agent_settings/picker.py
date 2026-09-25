"""Searchable terminal menus with persistent config actions."""

from typing import ClassVar, final, override

from textual import on
from textual.app import App, ComposeResult
from textual.binding import Binding, BindingType
from textual.widgets import Button, Footer, Header, Input, Label, OptionList
from textual.widgets.option_list import Option

SWITCH = "\x00switch"
FORK = "\x00fork"
DELETE = "\x00delete"


@final
class Picker(App[str]):
    CSS: ClassVar[str] = """
    Screen { align: center middle; }
    Input { margin: 1 2; width: 90%; }
    OptionList { margin: 0 2; width: 90%; height: 1fr; }
    Label { margin: 1 2; }
    Button { margin: 0 2; width: 90%; }
    """
    BINDINGS: ClassVar[list[BindingType]] = [
        Binding("escape", "cancel", "Cancel"),
        Binding("down", "move(1)", show=False, priority=True),
        Binding("up", "move(-1)", show=False, priority=True),
        Binding("ctrl+s", "manage('switch')", "Switch config", show=False, priority=True),
        Binding("ctrl+n", "manage('fork')", "Fork config", show=False, priority=True),
        Binding("ctrl+d", "manage('delete')", "Delete config", show=False, priority=True),
    ]

    def __init__(self, labels: list[str], prompt: str, *, manage: bool = False) -> None:
        super().__init__()
        self.labels = labels
        self.title = prompt
        self.manage = manage

    @override
    def compose(self) -> ComposeResult:
        yield Header()
        yield Label(self.title, markup=False)
        yield Input(placeholder="Search models or providers…" if self.manage else "Search…")
        yield OptionList(*(Option(label, id=str(i)) for i, label in enumerate(self.labels)))
        if self.manage:
            yield Button("Switch config   Ctrl+S", id="switch")
            yield Button("Fork current config   Ctrl+N", id="fork")
            yield Button("Delete current config   Ctrl+D", id="delete", variant="error")
        yield Footer()

    def action_move(self, direction: int) -> None:
        options = self.query_one(OptionList)
        if options.option_count:
            options.highlighted = ((options.highlighted or 0) + direction) % options.option_count

    @on(Input.Changed)
    def filter_options(self, event: Input.Changed) -> None:
        options = self.query_one(OptionList)
        options.clear_options()
        options.add_options(
            Option(label, id=str(i))
            for i, label in enumerate(self.labels)
            if event.value.casefold() in label.casefold()
        )
        options.highlighted = 0 if options.option_count else None

    @on(Input.Submitted)
    def submit_search(self) -> None:
        options = self.query_one(OptionList)
        if options.highlighted is not None:
            self.choose(options.get_option_at_index(options.highlighted))

    @on(OptionList.OptionSelected)
    def select_option(self, event: OptionList.OptionSelected) -> None:
        self.choose(event.option)

    def choose(self, option: Option) -> None:
        if option.id is not None:
            self.exit(self.labels[int(option.id)])

    @on(Button.Pressed)
    def pressed(self, event: Button.Pressed) -> None:
        self.action_manage(event.button.id or "")

    def action_manage(self, action: str) -> None:
        if self.manage:
            self.exit({"switch": SWITCH, "fork": FORK, "delete": DELETE}[action])

    def action_cancel(self) -> None:
        self.exit()


@final
class TextPrompt(App[str]):
    CSS: ClassVar[str] = (
        "Screen { align: center middle; } Label, Input { width: 80%; margin: 1 2; }"
    )
    BINDINGS: ClassVar[list[BindingType]] = [Binding("escape", "cancel", "Cancel")]

    def __init__(self, prompt: str) -> None:
        super().__init__()
        self.prompt = prompt

    @override
    def compose(self) -> ComposeResult:
        yield Label(self.prompt, markup=False)
        yield Input()
        yield Footer()

    @on(Input.Submitted)
    def submitted(self, event: Input.Submitted) -> None:
        if event.value.strip():
            self.exit(event.value.strip())

    def action_cancel(self) -> None:
        self.exit()


def pick(labels: list[str], prompt: str, *, manage: bool = False) -> str:
    result = Picker(labels, prompt, manage=manage).run()
    if result is None:
        raise KeyboardInterrupt
    return result


def ask(prompt: str) -> str:
    result = TextPrompt(prompt).run()
    if result is None:
        raise KeyboardInterrupt
    return result
