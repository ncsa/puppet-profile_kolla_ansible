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
  #include stdlib
  include python

# Unable to resolve duplicate declaration errors in the control repo. Taking
# this out. Software package dependencies will have to be managed through
# other, overlapping, package resources.
  # Install dependencies
  # https://docs.openstack.org/kolla-ansible/latest/user/quickstart.html
  #$deps = [
  # 'git',
  #  'python3-devel',
  #  'libffi-devel',
  #  'gcc',
  #  'openssl-devel',
  #  'python3-libselinux',
  #]

  # package { $deps:
  #   ensure => 'present',
  # }
  # use ensure_packages to avoid duplicate package errors
  # stdlib::ensure_packages ($deps, { 'ensure' => 'present' })
  # NCSA modules are dependent on a pretty old stdlib version.
  # Dropping namespaced call for the old version to work
  # ensure_packages($deps, { 'ensure' => 'present' })

  # Make sure we have python3 and latest pip
  # https://forge.puppet.com/modules/puppet/python/readme
  # class { 'python':
  #  version => 'system',
  #  pip     => 'latest',
  #  dev     => 'present',
  # }

  # Install Kolla VENV
  # Get paths
  $kolla_deploy = lookup('profile_kolla_ansible::deploy_dir')
  if ( empty($kolla_deploy) ) {
    fail ('No deploy directory specified. Cannot continue.')
  }

  $venv_dir = lookup('profile_kolla_ansible::venv_dir')
  if ( empty($venv_dir) ) {
    fail ('No virtual environment directory specified. Cannot continue.')
  }

  #may need to precreate the kolla_deploy dir and make it a requirement here but
  #have to check if pyenv supports that (or does the directory creation itself)
  # Create the venv
  $kolla_venv = "${kolla_deploy}/${venv_dir}"
  python::pyvenv { $kolla_venv:
    ensure      => 'present',
    version     => 'system',
    systempkgs  => true,
    venv_dir    => $kolla_venv,
    pip_version => 'latest',
  }

  # Install Kolla-Ansible
  python::pip { 'kolla-ansible':
    ensure     => 'present',
    url        => 'git+https://opendev.org/openstack/kolla-ansible@master',
    virtualenv => $kolla_venv,
  }

  # Install config files
  # Lookup repo location. Must be a legit file resource.
  $cfg_src = lookup('profile_kolla_ansible::file_src')
  if ( empty($cfg_src) ) {
    fail ('No file repository defined for kolla configuration. Cannot continue.')
  }

  $kolla_etc = lookup('profile_kolla_ansible::etc_dir')
  if ( empty($kolla_etc) ) {
    notify ('Using default kolla-ansible directory: /etc/kolla')
    $kolla_etc = '/etc/kolla'
  }

  # Determine which cluster files to install
  $cluster = lookup('profile_kolla_ansible::cluster_name')
  if ( empty($cluster) ) {
    fail ('No cluster defined for kolla configuration. Cannot continue.')
  }

  # Make sure the kolla config directory exists
  file { $kolla_etc:
    ensure => 'directory',
    mode   => '0755',
    owner  => 'root',
    group  => 'root',
  }

  # The global config file
  file { 'globals.yml':
    ensure => file,
    path   => "${kolla_etc}/${cluster}/globals.yml",
    owner  => 'root',
    group  => 'root',
    mode   => '0600',
    source => "${cfg_src}/${cluster}/kolla/globals.yml",
  }

  # The password file
  file { 'passwords.yml':
    ensure => file,
    path   => "${kolla_etc}/${cluster}/passwords.yml",
    owner  => 'root',
    group  => 'root',
    mode   => '0600',
    source => "${cfg_src}/${cluster}/kolla/passwords.yml",
  }

  # The admin-rc file
  file { 'admin-openrc.sh':
    ensure => file,
    path   => "${kolla_etc}/${cluster}/admin-openrc.sh",
    owner  => 'root',
    group  => 'root',
    mode   => '0600',
    source => "${cfg_src}/${cluster}/kolla/admin-openrc.sh",
  }

  # multinode
  file { 'multinode':
    ensure => file,
    path   => "${kolla_deploy}/multinode",
    owner  => 'root',
    group  => 'root',
    mode   => '0600',
    source => "${cfg_src}/${cluster}/kolla/multinode",
  }

  # Ansible config
  file { 'ansible.cfg':
    ensure => file,
    path   => '/etc/ansible/ansible.cfg',
    owner  => 'root',
    group  => 'root',
    mode   => '0600',
    source => "${cfg_src}/${cluster}/ansible.cfg",
  }

  # This painful construct allows requiring that the venv is ready before
  # attempting to call kolla-ansible in it.
  exec { 'has_kolla_venv':
    command => '/bin/true',
    onlyif  => "/usr/bin/test -f ${kolla_venv}/pyvenv.cfg",
  }

  # Install Ansible Galaxy (similar to puppet-forge)
  exec { 'ansible-galaxy':
    #command => "source ${kolla_venv}/bin/activate ; kolla-ansible install-deps",
    #creates => "${kolla_venv}/lib/python3.9/site-packages/ansible/galaxy",
    #require => Exec['has_kolla_venv'],
    command => "${kolla_venv}/bin/python kolla-ansible install-deps",
    cwd     => $kolla_venv,
    require => Exec['has_kolla_venv'],
    creates => "${kolla_venv}/lib/python3.9/site-packages/ansible/galaxy",
  }

  # Install python openstack client
  python::pip { 'python-openstack':
    ensure  => 'present',
    #require => Package['python3-pip'],
  }

  $create_link = lookup ('profile_kolla_ansible::link_cluster_to_venv')
  if $create_link {
    file { "${kolla_deploy}/${cluster}":
      ensure  => 'link',
      target  => $kolla_venv,
      require => File[$kolla_venv],
    }
  }
}
