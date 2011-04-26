#-- license
#
#  Based on original code by Justin Mecham and James Hunt
#  at http://rubyforge.org/projects/activedirectory
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#++ license

module ActiveDirectory
	#
	# Base class for all Ruby/ActiveDirectory Entry Objects (like User and Group)
	#
	class Base
		#
		# A Net::LDAP::Filter object that doesn't do any filtering
		# (outside of check that the CN attribute is present.  This
		# is used internally for specifying a 'no filter' condition
		# for methods that require a filter object.
		#
		NIL_FILTER = Net::LDAP::Filter.pres('cn')

		#
		# When locking out an account, use these values which do not usually
		# change.  If the domain policy changes, change these values.
		# 6000000000 = 10 minutes
		AD_LOCKOUT_DURATION  = 6000000000
		AD_LOCKOUT_THRESHOLD = 3

		@@ldap = nil

		#
		# Configures the connection for the Ruby/ActiveDirectory library.
		#
		# For example:
		#
		#   ActiveDirectory::Base.setup(
		#     :host => 'domain_controller1.example.org',
		#     :port => 389,
		#     :base => 'dc=example,dc=org',
		#     :auth => {
		#       :username => 'querying_user@example.org',
		#       :password => 'querying_users_password'
		#     }
		#   )
		#
		# This will configure Ruby/ActiveDirectory to connect to the domain
		# controller at domain_controller1.example.org, using port 389. The
		# domain's base LDAP dn is expected to be 'dc=example,dc=org', and
		# Ruby/ActiveDirectory will try to bind as the
		# querying_user@example.org user, using the supplied password.
		#
		# Currently, there can be only one active connection per
		# execution context.
		#
		# For more advanced options, refer to the Net::LDAP.new
		# documentation.
		#
		def self.setup(settings)
			@@settings = settings
			@@ldap = Net::LDAP.new(settings)
		end

		def self.error
			"#{@@ldap.get_operation_result.code}: #{@@ldap.get_operation_result.message}"
		end

		##
		# Return the last errorcode that ldap generated
		def self.error_code
			@@ldap.get_operation_result.code
		end

		##
		# Check to see if the last query produced an error
		# Note: Invalid username/password combinations will not
		# produce errors
		def self.error?
			@@ldap.nil? ? false : @@ldap.get_operation_result.code != 0
		end

		##
		# Check to see if we are connected to the LDAP server
		# This method will try to connect, if we haven't already
		def self.connected?
			begin
				@@ldap.nil? ? false : @@ldap.bind
			rescue Net::LDAP::LdapError => e
				false
			end
		end

		def self.filter # :nodoc:
			NIL_FILTER 
		end

		def self.required_attributes # :nodoc:
			{}
		end

		#
		# Check to see if any entries matching the passed criteria exists.
		#
		# Filters should be passed as a hash of 
		# attribute_name => expected_value, like:
		#
		#   User.exists?(
		#     :sn => 'Hunt',
		#     :givenName => 'James'
		#   )
		#
		# which will return true if one or more User entries have an
		# sn (surname) of exactly 'Hunt' and a givenName (first name)
		# of exactly 'James'.
		#
		# Partial attribute matches are available.  For instance,
		#
		#   Group.exists?(
		#     :description => 'OldGroup_*'
		#   )
		#
		# would return true if there are any Group objects in
		# Active Directory whose descriptions start with OldGroup_,
		# like OldGroup_Reporting, or OldGroup_Admins.
		#
		# Note that the * wildcard matches zero or more characters,
		# so the above query would also return true if a group named
		# 'OldGroup_' exists.
		# 
		def self.exists?(filter_as_hash)
			criteria = make_filter_from_hash(filter_as_hash) & filter
			(@@ldap.search(:filter => criteria).size > 0)
		end

		#
		# Whether or not the entry has local changes that have not yet been
		# replicated to the Active Directory server via a call to Base#save
		#
		def changed?
			!@attributes.empty?
		end

		def self.make_filter_from_hash(hash) # :nodoc:
			return NIL_FILTER if hash.nil? || hash.empty?

			#I'm sure there's a better way to do this
			#Grab the first one, then do the rest
			key, value = hash.shift
			f = Net::LDAP::Filter.eq(key, encode_field(key, value).to_s)
			
			hash.each do |key, value|
				f = f & Net::LDAP::Filter.eq(key, encode_field(key, value).to_s)
			end

			return f
		end

		#
		# Performs a search on the Active Directory store, with similar
		# syntax to the Rails ActiveRecord#find method.
		#
		# The first argument passed should be
		# either :first or :all, to indicate that we want only one
		# (:first) or all (:all) results back from the resultant set.
		#
		# The second argument should be a hash of attribute_name =>
		# expected_value pairs.
		#
		#   User.find(:all, :sn => 'Hunt')
		#
		# would find all of the User objects in Active Directory that
		# have a surname of exactly 'Hunt'.  As with the Base.exists?
		# method, partial searches are allowed.
		#
		# This method always returns an array if the caller specifies
		# :all for the search type (first argument).  If no results
		# are found, the array will be empty.
		#
		# If you call find(:first, ...), you will either get an object
		# (a User or a Group) back, or nil, if there were no entries
		# matching your filter.
		#
		def self.find(*args)
			return false unless connected?

			options = {
				:filter => NIL_FILTER,
				:in => ''
			}
			options.merge!(:filter => args[1]) unless args[1].nil?
			options[:in] = [ options[:in].to_s, @@settings[:base] ].delete_if { |part| part.empty? }.join(",")
			if options[:filter].is_a? Hash
				options[:filter] = make_filter_from_hash(options[:filter])
			end
			options[:filter] = options[:filter] & filter unless self.filter == NIL_FILTER
			
			if (args.first == :all)
				find_all(options)
			elsif (args.first == :first)
				find_first(options)
			else
				raise ArgumentError, 'Invalid specifier (not :all, and not :first) passed to find()'
			end
		end

		def self.find_all(options)
			results = []
			@@ldap.search(:filter => options[:filter], :base => options[:in], :return_result => false) do |entry|
				results << new(entry)
			end
			results
		end

		def self.find_first(options)
			@@ldap.search(:filter => options[:filter], :base => options[:in], :return_result => false) do |entry|
				return new(entry)
			end
		end

		def self.method_missing(name, *args) # :nodoc:
			name = name.to_s
			if (name[0,5] == 'find_')
				find_spec, attribute_spec = parse_finder_spec(name)
				raise ArgumentError, "find: Wrong number of arguments (#{args.size} for #{attribute_spec.size})" unless args.size == attribute_spec.size
				filters = {}
				[attribute_spec,args].transpose.each { |pr| filters[pr[0]] = pr[1] }
				find(find_spec, :filter => filters)
			else
				super name.to_sym, args
			end
		end

		def self.parse_finder_spec(method_name) # :nodoc:
			# FIXME: This is a prime candidate for a
			# first-class object, FinderSpec

			method_name = method_name.gsub(/^find_/,'').gsub(/^by_/,'first_by_')
			find_spec, attribute_spec = *(method_name.split('_by_'))
			find_spec = find_spec.to_sym
			attribute_spec = attribute_spec.split('_and_').collect { |s| s.to_sym }

			return find_spec, attribute_spec
		end

		def ==(other) # :nodoc:
			return false if other.nil?
			other.objectGUID == objectGUID
		end

		#
		# Returns true if this entry does not yet exist in Active Directory.
		#
		def new_record?
			@entry.nil?
		end

		#
		# Refreshes the attributes for the entry with updated data from the
		# domain controller.
		#
		def reload
			return false if new_record?

			@entry = @@ldap.search(:filter => Net::LDAP::Filter.eq('distinguishedName',distinguishedName))[0]
			return !@entry.nil?
		end

		#
		# Updates a single attribute (name) with one or more values
		# (value), by immediately contacting the Active Directory
		# server and initiating the update remotely.
		#
		# Entries are always reloaded (via Base.reload) after calling
		# this method.
		#
		def update_attribute(name, value)
			update_attributes(name.to_s => value)
		end

		#
		# Updates multiple attributes, like ActiveRecord#update_attributes.
		# The updates are immediately sent to the server for processing,
		# and the entry is reloaded after the update (if all went well).
		#
		def update_attributes(attributes_to_update)
			return true if attributes_to_update.empty?

			operations = []
			attributes_to_update.each do |attribute, values|
				if values.nil? || values.empty?
					operations << [ :delete, attribute, nil ]
				else
					values = [values] unless values.is_a? Array
					values = values.collect { |v| v.to_s }

					current_value = begin
						@entry.send(attribute)
					rescue NoMethodError
						nil
					end

					operations << [ (current_value.nil? ? :add : :replace), attribute, values ]
				end
			end

			@@ldap.modify(
				:dn => distinguishedName,
				:operations => operations
			) && reload
		end

		#
		# Create a new entry in the Active Record store.
		#
		# dn is the Distinguished Name for the new entry.	This must be
		# a unique identifier, and can be passed as either a Container
		# or a plain string.
		#
		# attributes is a symbol-keyed hash of attribute_name => value
		# pairs.
		#
		def self.create(dn,attributes)
			return nil if dn.nil? || attributes.nil?
			begin
				attributes.merge!(required_attributes)
				if @@ldap.add(:dn => dn.to_s, :attributes => attributes)
					return find_by_distinguishedName(dn.to_s)
				else
					return nil
				end
			rescue
				return nil
			end
		end

		#
		# Deletes the entry from the Active Record store and returns true
		# if the operation was successfully.
		#
		def destroy
			return false if new_record?

			if @@ldap.delete(:dn => distinguishedName)
				@entry = nil
				@attributes = {}
				return true
			else
				return false
			end
		end

		#
		# Saves any pending changes to the entry by updating the remote
		# entry.
		#
		def save
			if update_attributes(@attributes)
				@attributes = {}
				return true
			else
				return false
			end
		end

		#
		# This method may one day provide the ability to move entries from
		# container to container. Currently, it does nothing, as we are
		# waiting on the Net::LDAP folks to either document the
		# Net::LDAP#modrdn method, or provide a similar method for
		# moving / renaming LDAP entries.
		#
		def move(new_rdn)
			return false if new_record?
			puts "Moving #{distinguishedName} to RDN: #{new_rdn}"

			settings = @@settings.dup
			settings[:port] = 636
			settings[:encryption] = { :method => :simple_tls }

			ldap = Net::LDAP.new(settings)

			if ldap.rename(
				:olddn => distinguishedName,
				:newrdn => new_rdn,
				:delete_attributes => false
			)
				return true
			else
				puts Base.error
				return false
			end
		end

		# FIXME: Need to document the Base::new
		def initialize(attributes = {}) # :nodoc:
			if attributes.is_a? Net::LDAP::Entry
				@entry = attributes
				@attributes = {}
			else
				@entry = nil
				@attributes = attributes
			end
		end

		## 
		# Grabs the field type depending on the class it is called from 
		# Takes the field name as a parameter
		def self.get_field_type(name)
			#Extract class name
			klass = self.name[/.*::(.*)/, 1]
			type = ::ActiveDirectory.special_fields[klass.classify.to_sym][name.to_s.downcase.to_sym]
			type.to_s.classify unless type.nil?
		end

		def self.decode_field(name, value)
			#Extract class name
			type = get_field_type name
			return ::ActiveDirectory::FieldType::const_get(type).decode(value) if !type.nil? and ::ActiveDirectory::FieldType::const_defined? type
			return value
		end

		def self.encode_field(name, value)
			type = get_field_type name
			return ::ActiveDirectory::FieldType::const_get(type).encode(value) if !type.nil? and ::ActiveDirectory::FieldType::const_defined? type
			return value
		end

		def method_missing(name, args = []) # :nodoc:
			name = name.to_s.downcase

			if name[-1,1] == '='
				name.chop!
				@attributes[name.to_sym] = encode_field(name, args)
			end

			return decode_field(name, @attributes[name.to_sym]) if @attributes.has_key?(name.to_sym)
				
			if @entry
				begin
					value = @entry.send(name.to_sym)
					value = value.first if value.kind_of?(Array) && value.size == 1
					value = value.to_s if value.nil? || value.size == 1
					return self.class.decode_field(name, value)
				rescue NoMethodError
					return nil
				end
			end

			super
		end

	end
end
