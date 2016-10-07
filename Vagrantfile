Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/trusty64"
  config.vm.hostname = "ace"
  config.vm.synced_folder ".", "/vagrant"

  config.vm.network "forwarded_port", guest: 8080, host: 8080
  config.vm.provision "shell", path: "./provision.sh"
  config.vm.provider "virtualbox" do |v|
    # Running Dialyzer takes up a lot of memory and does not give useful errors if it runs out of memory.
    # http://stackoverflow.com/questions/39854839/dialyxir-mix-task-to-create-plt-exits-without-error-or-creating-table?noredirect=1#comment66998902_39854839
    v.memory = 3000
    v.cpus = 2
  end
end
