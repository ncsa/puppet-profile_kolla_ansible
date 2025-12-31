# @summary Install Kolla-Ansible and its configuration files.
#
# This will install all necessary software and kolla-ansible
# itself to a system then sync the (already) configured 
# kolla configuration files. It will NOT execute kolla-ansible
# EXCEPT to run 'install-deps'. Starting KA/Openstack is
# left to the operator. Other necessary system configuration
# e.g. firewalls, ssh configuration and other underlying requirements
# are left to other modules.
#
# This is currently set up for Rocky(RH) packages. Support for other
# OS's is not currently planned.
#
# @example
#   include profile_kolla_ansible
class profile_kolla_ansible {
  # Install dependencies
  $deps = [
    "git",
    "python3-devel",
    "libffi-devel",
    "gcc",
    "openssl-devel",
    "python3-libselinux",
  ]

  package { $deps:
    ensure => 'present',
  }

  # Make sure we have python3 and latest pip
  # https://forge.puppet.com/modules/puppet/python/readme
  class { 'python':
    version => 'system',
    pip     => 'latest',
    dev     => 'present',
  }

  # Install Kolla VENV
  $kolla_venv = '/opt/openstack/deploy/prod' # move to a lookup
  python::pyenv { $kolla_venv:
    ensure      => 'present',
    version     => 'system',
    systempkgs  => 'true',
    venv_dir    => "${kolla_venv}",
    pip_version => 'latest',
  }

  # Install Kolla-Ansible
  python::pip { 'kolla-ansible':
    ensure     => 'present',
    url        => 'git+https://opendev.org/openstack/kolla-ansible@master',
    virtualenv => "${kolla_venv}",
  }
  
  # Create kolla config directory
  file { '/etc/kolla':
    ensure => 'directory',
    mode   => '0755',
    owner  => 'root',
    group  => 'root',
  }

  # Install config files -- recommend we do this the same way as the globus-compute
  # config files, using the puppet file resource from the xcat master httpd server
  # ex
  # # Lookup our required endpoint information
  # $endpoint_name = lookup('profile_globus::compute_agent::endpoint_name')
  # if ( empty($endpoint_name) ) {
  #   fail ('No globus compute endpoint name defined. Cannot continue.')
  # } else {
  #   notify { 'endpoint_name':
  #     message => "Setting globus compute endpoint name to ${endpoint_name}.",
  #   }
  # }
  # ## The endpoint config file
  #   file { 'ep_config':
  #     ensure => file,
  #     path   => "/root/.globus_compute/${endpoint_name}/config.yaml",
  #     owner  => 'root',
  #     group  => 'root',
  #     mode   => '0600',
  #     source => "${config_src}/endpoints/${endpoint_name}/config.yaml",
  #   }
  # globals.yml
  # passwords.yml
  # multinode
  # Other...???

  # This painful construct allows requiring that the venv is ready before
  # attempting to call kolla-ansible in it.
  exec { 'has_kolla_venv':
  command => '/bin/true',
  onlyif  => "test -f ${kolla_venv}/pyvenv.cfg",
}

  # Install Ansible Galaxy (similar to puppet-forge)
  exec { 'ansible-galaxy':
    command => "source ${kolla_venv}/bin/activate ; kolla-ansible install-deps",
    require => Package['python3'],
    creates => "${kolla_venv}/lib/python3.9/site-packages/ansible/galaxy",
    require => Exec['has_kolla_venv'],
  }
}
