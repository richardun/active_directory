# coding: utf-8
require File.expand_path('../lib/active_directory/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ['Richard Navarrete', 'Elia Schito']
  gem.email         = ['richardun@gmail.com', 'elia@schito.me']
  gem.description   = %q{ActiveDirectory uses Net::LDAP to provide a means of accessing and modifying an Active Directory data store.  This is a fork of the activedirectory gem.}
  gem.summary       = %q{An interface library for accessing Microsoft's Active Directory.}
  gem.homepage      = 'http://github.com/richardun/active_directory'
  gem.license       = 'MIT-LICENSE'

  gem.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.extra_rdoc_files = ['README.md']
  gem.name          = 'active_directory'
  gem.require_paths = ['lib']
  gem.version       = ActiveDirectory::VERSION
  
  gem.add_runtime_dependency 'activesupport', '~> 3.0'
  gem.add_runtime_dependency 'net-ldap', '>= 0.1.1'
end
