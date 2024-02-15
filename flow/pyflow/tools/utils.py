from os import path
from .blueprint import call_cmd

def call_util_script(script: str, args: list[str], utils_dir: str, env: dict[str, str], logfile: str):
	call_cmd(
		path.join(utils_dir, script),
		args,
		env,
		logfile
	)