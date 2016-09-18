Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/trusty64"
  config.vm.hostname = "ace"
  config.vm.synced_folder ".", "/vagrant"

  config.vm.network "forwarded_port", guest: 8080, host: 8080
  config.vm.provision "shell", path: "./provision.sh"
end
