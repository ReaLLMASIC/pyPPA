from os import path
from . import __call_tool

def call_util_script(script: str, args: list[str], utils_dir: str, env: dict[str, str], logfile: str):
	__call_tool(
		path.join(utils_dir, script),
		args,
		env,
		logfile
	)