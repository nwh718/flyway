import subprocess
subprocess.run(['git', 'restore', 'flyway-commandline/pom.xml'])
subprocess.run(['git', 'clean', '-fd'])
