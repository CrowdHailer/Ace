# Git is installed so that mix can use github.com as a source of dependencies
apt-get install -y git

# Install the Elixir and Erlang languages as required.
wget https://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb
sudo dpkg -i erlang-solutions_1.0_all.deb
sudo apt-get update
sudo apt-get install -y erlang
sudo apt-get install esl-erlang
sudo apt-get install -y elixir
