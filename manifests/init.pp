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
  include dirtree
  include python

# Unable to resolve duplicate declaration errors in the control repo.
# Software package dependencies will have to be managed through
# other, overlapping, package resources.
  # Install dependencies
  # https://docs.openstack.org/kolla-ansible/latest/user/quickstart.html
  #$deps = [
  # 'git',
  #  'python3-devel',
  #  'libffi-devel',
  #  'gcc',
  #  'openssl-devel',
  #  'python3-libselinux',k
  #]

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

  # Create the venv
  $kolla_venv = "${kolla_deploy}/${venv_dir}"
  python::pyvenv { $kolla_venv:
    ensure      => 'present',
    version     => 'system',
    systempkgs  => true,
    venv_dir    => $kolla_venv,
    pip_version => 'latest',
  }

  # Need to add configurable version overrides for KA, Ansible and python...
  $ansible_version = '5.10.0'
  # Install Anisble - Kolla does not do this.
  python::pip { 'ansible':
    ensure     => $ansible_version,
    virtualenv => $kolla_venv,
    require => Exec['has_kolla_venv'],
  }

  # It's not clear why this ins't getting installed so forcing it here.
  python::pip { 'PyYAML':
    ensure     => 'present',
    virtualenv => $kolla_venv,
    require => Exec['has_kolla_venv'],
  }

  #$ka_version = "14.11.0"
  # Install Kolla-Ansible (the pip module doesn't seem able to handle this)
  $ka_version = 'yoga-eol' # The pip module does not suppport non-numeric tags.
  exec { 'kolla-ansible':
    command => "/bin/bash -c \". ${kolla_venv}/bin/activate && pip install git+https://opendev.org/openstack/kolla-ansible@${ka_version}\"",
    cwd     => $kolla_venv,
    require => Exec['has_kolla_venv'],
    creates => "${kolla_venv}/bin/kolla-ansible",
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

  # Make sure the install directories exist
  $kolla_etc_dirs = dirtree($kolla_etc)
  file { $kolla_etc_dirs:
    ensure => 'directory',
    #mode   => '0755',
    owner  => 'root',
    group  => 'root',
  }

  $kolla_deploy_dirs = dirtree($kolla_deploy)
  file { $kolla_deploy_dirs:
    ensure => 'directory',
    #mode   => '0755',
    owner  => 'root',
    group  => 'root',
  }

  file { '/etc/ansible':
    ensure => 'directory',
    mode   => '0700',
    owner  => 'root',
    group  => 'root',
  }

  # The global config file
  file { 'globals.yml':
    ensure  => file,
    path    => "${kolla_etc}/globals.yml",
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    source  => "${cfg_src}/${cluster}/kolla/globals.yml",
    require => File[$kolla_etc],
  }

  # The password file
  file { 'passwords.yml':
    ensure  => file,
    path    => "${kolla_etc}/passwords.yml",
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    source  => "${cfg_src}/${cluster}/kolla/passwords.yml",
    require => File[$kolla_etc],
  }

  # The admin-rc file
  file { 'admin-openrc.sh':
    ensure  => file,
    path    => "${kolla_etc}/admin-openrc.sh",
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    source  => "${cfg_src}/${cluster}/kolla/admin-openrc.sh",
    require => File[$kolla_etc],
  }

  # multinode
  file { 'multinode':
    ensure  => file,
    path    => "${kolla_deploy}/multinode",
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    source  => "${cfg_src}/${cluster}/kolla/multinode",
    require => File[$kolla_deploy],
  }

  # Ansible config
  file { 'ansible.cfg':
    ensure  => file,
    path    => '/etc/ansible/ansible.cfg',
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    source  => "${cfg_src}/${cluster}/ansible.cfg",
    require => File['/etc/ansible'],
  }

  # This painful construct is for requiring various parts
  # are ready to control ordering. There is probably a
  # python class way to do this but this seems to work...
  exec { 'has_kolla_venv':
    command => '/bin/true',
    onlyif  => "/usr/bin/test -f ${kolla_venv}/pyvenv.cfg",
  }
  exec { 'has_kolla_ansible':
    command => '/bin/true',
    onlyif  => "/usr/bin/test -f ${kolla_venv}/bin/kolla-ansible",
  }
  exec { 'has_ansible':
    command => '/bin/true',
    onlyif  => "/usr/bin/test -f ${kolla_venv}/bin/ansible",
  }

  # Install Ansible Galaxy (similar to puppet-forge)
  exec { 'ansible-galaxy':
    command => "/bin/bash -c \". ${kolla_venv}/bin/activate && kolla-ansible install-deps\"",
    cwd     => $kolla_venv,
    require => [
      Exec['has_kolla_ansible'],
      Exec['has_ansible'],
    ],
    creates => "${kolla_venv}/lib/python3.9/site-packages/ansible/galaxy",
  }

  # Install python openstack client
  python::pip { 'python-openstackclient':
    ensure  => 'present',
    require => Exec['has_kolla_venv'],
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
