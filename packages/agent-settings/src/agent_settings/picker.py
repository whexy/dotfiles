import subprocess

from agent_settings.errors import SettingsError


def pick(fzf: str, labels: list[str], prompt: str) -> str:
    """Return the label chosen in fzf; cancelling raises KeyboardInterrupt."""
    result = subprocess.run(
        [fzf, "--reverse", "--height=~100%", f"--prompt={prompt}> "],
        input="\n".join(labels) + "\n",
        text=True,
        stdout=subprocess.PIPE,
        check=False,
    )
    if result.returncode in (1, 130):
        raise KeyboardInterrupt
    choice = result.stdout.strip()
    if result.returncode or choice not in labels:
        raise SettingsError("model selector failed")
    return choice
