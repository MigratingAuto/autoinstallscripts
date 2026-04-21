To move the following files I reccomned using SCP

for password based authenatcation
scp /path/to/local/file.txt user@192.168.1.10:/home/user/

for ssh key authenatcation
scp -i ~/.ssh/id_rsa file.txt user@192.168.1.10:/home/user/