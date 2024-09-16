#!/bin/bash
sudo sysctl vm.nr_hugepages=3072

# Запустить новую сессию tmux с именем my_session и не отсоединяться
tmux new-session -d -s xmr_mining

# Разделить окно по горизонтали
tmux split-window -h

# Переключиться на первую панель (левая)
tmux select-pane -t 0

# Разделить левую панель по вертикали
tmux split-window -v

# Переключиться на вторую панель (правая)
tmux select-pane -t 1

# Разделить правую панель по вертикали
tmux split-window -v

# Запуск команд в каждой панели

# Первая панель (верхняя левая)
tmux select-pane -t 0
#tmux send-keys 'monerod --zmq-pub tcp://127.0.0.1:18083 --out-peers 32 --in-peers 64 --add-priority-node=p2pmd.xmrvsbeast.com:18080 --add-priority-node=nodes.hashvault.pro:18080 --disable-dns-checkpoints --enable-dns-blocklist' C-m
tmux send-keys '~/monerod_run.sh' C-m

# Вторая панель (нижняя левая)
tmux select-pane -t 2
tmux send-keys 'sysctl vm.nr_hugepages' C-m
tmux send-keys 'p2pool --host 127.0.0.1 --mini --wallet 43UgFYo22kH47LqJnSUHXsPHzQh92caAv62jVvj7vvSmXebDXH5cpsr4iTQQwYMwRU2GcHMZrSowESmrmQ5XQEm58fFR3Nm'

# Третья панель (верхняя правая)
tmux select-pane -t 1
#tmux send-keys 'sudo xmrig -u x+1730000000 -o 127.0.0.1:3333 -t 16' #full
tmux send-keys 'sudo xmrig -u x+1730000000 -o 127.0.0.1:3333 -t 16' #mini


# Четвертая панель (нижняя правая)
tmux select-pane -t 3
tmux send-keys 'htop' C-m

# Подключиться к сессии
tmux attach-session -t xmr_mining
