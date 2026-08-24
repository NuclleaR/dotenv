alias mnt-box='mkdir -p ~/mnt/suse-server && sshfs suse-server:/home/serhii ~/mnt/suse-server -o reconnect,ServerAliveInterval=15'
alias umnt-box='fusermount3 -u ~/mnt/suse-server'