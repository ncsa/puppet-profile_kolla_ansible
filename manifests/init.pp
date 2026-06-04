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
  #  'python3-libselinux',
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

  # Install Ansible - Kolla Ansible requires at least Ansible 4 and supports up to 5
  # https://docs.openstack.org/kolla-ansible/yoga/user/quickstart.html
  exec { 'ansible':
    command => "/bin/bash -c \". ${kolla_venv}/bin/activate && pip install 'ansible>=4,<6'\"",
    cwd     => $kolla_venv,
    require => Exec['has_kolla_venv'],
    before  => Exec['kolla-ansible'],
    creates => "${kolla_venv}/bin/ansible",
  }

  # PyYAML must be installed before kolla-ansible to ensure proper dependency resolution
  python::pip { 'PyYAML':
    ensure     => 'present',
    virtualenv => $kolla_venv,
    require    => Exec['has_kolla_venv'],
    before     => Exec['kolla-ansible'],
  }

  # Install Kolla-Ansible via exec since python::pip doesn't support git+ URLs with refs
  # https://docs.openstack.org/kolla-ansible/yoga/user/quickstart.html
  $ka_version = 'yoga-eol'
  exec { 'kolla-ansible':
    command => "/bin/bash -c \". ${kolla_venv}/bin/activate && pip install 'git+https://opendev.org/openstack/kolla-ansible@${ka_version}'\"",
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

 # $kolla_etc = lookup('profile_kolla_ansible::etc_dir', default_value => '/etc/kolla')

  # Determine which cluster files to install
  $cluster = lookup('profile_kolla_ansible::cluster_name')
  if ( empty($cluster) ) {
    fail ('No cluster defined for kolla configuration. Cannot continue.')
  }

  # # Make sure the install directories exist
  # $kolla_etc_dirs = dirtree($kolla_etc)
  # file { $kolla_etc_dirs:
  #   ensure => 'directory',
  #   #mode   => '0755',
  #   owner  => 'root',
  #   group  => 'root',
  # }

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

  # # The global config file
  # file { 'globals.yml':
  #   ensure  => file,
  #   path    => "${kolla_etc}/globals.yml",
  #   owner   => 'root',
  #   group   => 'root',
  #   mode    => '0600',
  #   source  => "${cfg_src}/${cluster}/kolla/globals.yml",
  #   require => File[$kolla_etc],
  # }

  # # The password file
  # file { 'passwords.yml':
  #   ensure  => file,
  #   path    => "${kolla_etc}/passwords.yml",
  #   owner   => 'root',
  #   group   => 'root',
  #   mode    => '0600',
  #   source  => "${cfg_src}/${cluster}/kolla/passwords.yml",
  #   require => File[$kolla_etc],
  # }

  # # The admin-rc file
  # file { 'admin-openrc.sh':
  #   ensure  => file,
  #   path    => "${kolla_etc}/admin-openrc.sh",
  #   owner   => 'root',
  #   group   => 'root',
  #   mode    => '0600',
  #   source  => "${cfg_src}/${cluster}/kolla/admin-openrc.sh",
  #   require => File[$kolla_etc],
  # }

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

  # # Openstack config files
  # file { "${kolla_etc}/config":
  #   ensure  => directory,
  #   source  => "${cfg_src}/${cluster}/kolla/config",
  #   recurse => remote,
  #   require => File[$kolla_etc],
  # }

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
    unless  => "/usr/bin/test -d ${kolla_venv}/share/kolla-ansible",
  }

  # Install python openstack client in the venv with yoga constraints
  # https://docs.openstack.org/kolla-ansible/yoga/user/quickstart.html
  exec { 'python-openstackclient':
    command => "/bin/bash -c \". ${kolla_venv}/bin/activate && pip install python-openstackclient -c https://releases.openstack.org/constraints/upper/yoga\"",
    cwd     => $kolla_venv,
    require => Exec['has_kolla_venv'],
    creates => "${kolla_venv}/bin/openstack",
  }

  # Install osc-placement for nova placement API
  exec { 'osc-placement':
    command => "/bin/bash -c \". ${kolla_venv}/bin/activate && pip install osc-placement -c https://releases.openstack.org/constraints/upper/yoga\"",
    cwd     => $kolla_venv,
    require => Exec['python-openstackclient'],
    unless  => "/bin/bash -c \". ${kolla_venv}/bin/activate && pip show osc-placement\"",
  }

  $create_link = lookup ('profile_kolla_ansible::link_cluster_to_venv')
  if $create_link {
    file { "${kolla_deploy}/${cluster}":
      ensure  => 'link',
      target  => $kolla_venv,
      require => Python::Pyvenv[$kolla_venv],
    }
  }
}
