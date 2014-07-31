#!/bin/bash

# Usage: init.sh -webserver --environment prod1 --site a --repouser jimfdavies --reponame provtest-config

VERSION=0.0.1

if [ ${!#} == "--debug" ]
then
  function progress_bar {
  $@
  }
else
  function progress_bar {
    while :;do echo -n .;sleep 1;done &
    $@ > /dev/null
    kill $!; trap 'kill $!' SIGTERM
    echo -e "\e[0;32m done \e[0m"
  }
fi

# Install Puppet
# RHEL

echo -n "Installing Puppetlabs repo"
progress_bar yum install -y http://yum.puppetlabs.com/puppetlabs-release-el-6.noarch.rpm
echo -n "Installing Puppet"
progress_bar yum install -y puppet 2> /dev/null

# Process command line params

function print_version {
  echo $1 $2
}

function print_help {
  echo Heeelp.
}

function set_facter {
  export FACTER_$1=$2
  puppet apply -e "file { '/etc/facter': ensure => directory, mode => 0600 } -> file { '/etc/facter/facts.d': ensure => directory, mode => 0600 } -> file { '/etc/facter/facts.d/$1.txt': ensure => present, mode => 0600, content => '$1=$2' }" --logdest syslog > /dev/null
  echo -n "Facter says $1 is:"
  echo -e "\e[0;32m $(facter $1) \e[0m"
}

while test -n "$1"; do
  case "$1" in
  --help|-h)
    print_help
    exit 
    ;;
  --version|-v) 
    print_version $PROGNAME $VERSION
    exit
    ;; 
  --repouser|-u)
    set_facter init_repouser $2
    shift
    ;;
  --reponame|-n)
    set_facter init_reponame $2
    shift
    ;;
  --repoprivkeyfile|-k)
    set_facter init_repoprivkeyfile $2
    shift
    ;;
  --repobranch|-b)
    set_facter init_repobranch $2
    shift
    ;;
  --repodir|-d)
    set_facter init_repodir $2
    shift
    ;;
  --debug)
    shift
    ;;

  *)
    echo "Unknown argument: $1"
    print_help
    exit
    ;;
  esac
  shift
done

usagemessage="Error, USAGE: $(basename $0) --repouser|-u --reponame|-n --repoprivkeyfile|-k [--repobranch|-b] [--repodir|-d] [--help|-h] [--version|-v]"

# Define required parameters.
if [[ "$FACTER_init_repouser" == "" || "$FACTER_init_reponame" == "" || "$FACTER_init_repoprivkeyfile" == "" ]]; then
  echo $usagemessage
  exit 1
fi

# Set Git login params
echo "Injecting private ssh key"
GITHUB_PRI_KEY=$(cat $FACTER_init_repoprivkeyfile)
puppet apply -v -e "file {'ssh': path => '/root/.ssh/',ensure => directory}" > /dev/null
puppet apply -v -e "file {'id_rsa': path => '/root/.ssh/id_rsa',ensure => present, mode    => 0600, content => '$GITHUB_PRI_KEY'}" > /dev/null
puppet apply -v -e "file {'config': path => '/root/.ssh/config',ensure => present, mode    => 0644, content => 'StrictHostKeyChecking=no'}" > /dev/null
puppet apply -e "package { 'git': ensure => present }" > /dev/null

# Set some defaults if they aren't given on the command line.
[ -z "$FACTER_init_repobranch" ] && set_facter init_repobranch master
[ -z "$FACTER_init_repodir" ] && set_facter init_repodir /opt/$FACTER_init_reponame
# Clone private repo.
puppet apply -e "file { '$FACTER_init_repodir': ensure => absent, force => true }" > /dev/null
echo "Cloning $FACTER_init_repouser/$FACTER_init_reponame repo"
git clone -b $FACTER_init_repobranch git@github.com:$FACTER_init_repouser/$FACTER_init_reponame.git $FACTER_init_repodir

# Exit if the clone fails
if [ ! -d "$FACTER_init_repodir" ]
then
  echo "Failed to clone git@github.com:$FACTER_init_repouser/$FACTER_init_reponame.git" && exit 1
fi

# Link /etc/puppet to our private repo.
PUPPET_DIR="$FACTER_init_repodir/puppet"
rm -rf /etc/puppet ; ln -s $PUPPET_DIR /etc/puppet
puppet apply -e "file { '/etc/hiera.yaml': ensure => link, target => '/etc/puppet/hiera.yaml' }" > /dev/null

# # Install RVM to manage Ruby versions
echo "Installing RVM and latest Ruby"
curl -sSL https://get.rvm.io | bash
source /usr/local/rvm/scripts/rvm
rvm install $(rvm list remote | grep ruby | tail -1 | awk '{ print $NF }') --binary --debug --max-time 20


# # Use RVM to select specific Ruby version (2.1+) for use with Librarian-puppet
rvm use ruby

echo -n "Installing librarian-puppet"
progress_bar gem install librarian-puppet --no-ri --no-rdoc
echo -n "Installing Puppet gem"
progress_bar gem install puppet --no-ri --no-rdoc

# # Use RVM to revert Ruby version to back to system default (1.8.7)
rvm --default use system

