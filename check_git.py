import subprocess

result = subprocess.run(['git', 'diff'], capture_output=True, text=True)
with open('diff_output.txt', 'w') as f:
    f.write(result.stdout)

result_status = subprocess.run(['git', 'status'], capture_output=True, text=True)
with open('status_output.txt', 'w') as f:
    f.write(result_status.stdout)

result_log = subprocess.run(['git', 'log', '-n', '5'], capture_output=True, text=True)
with open('log_output.txt', 'w') as f:
    f.write(result_log.stdout)
