import subprocess

def __call_tool(tool: str, args: list[str], env: dict | None, logfile: str | None):
	for key in env:
		if type(env[key]) != str:
			print(key, env[key])

	if logfile:
		with open(logfile, 'w') as f:
			subprocess.run([tool, *args], env=env, stdout=f, stderr=f)
	else:
		subprocess.run([tool, *args], env=env)