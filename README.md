= Active Directory

Ruby Integration with Microsoft's Active Directory system based on original code by Justin Mecham and James Hunt at http://rubyforge.org/projects/activedirectory

See documentation on ActiveDirectory::Base for more information.

Caching:
Queries for membership and group membership are based on the distinguished name of objects.  Doing a lot of queries, especially for a Rails app, is a sizable slowdown.  To alleviate the problem, I've implemented a very basic cache for queries which search by :distinguishedname.  This is diabled by default.  All other queries are unaffected.


<h3>INSTALL (with Bundler for instance)</h3>
In Gemfile:
<pre>
gem 'net-ldap', :git => 'git://github.com/ruby-ldap/ruby-net-ldap.git'
gem 'active_directory', :git => 'git://github.com/richardun/active_directory.git'
</pre>

Note: You'll need to install ruby-net-ldap from GitHub until the maintainer pushes version 0.5.0 or later to rubygems.org.

Run bundle install: <em> :; is my prompt </em>
<pre>
:; bundle install
</pre>

<h3>Base setup</h3>
You can do this next part however you like, but I put the settings global variable in ../config/initializers/ad.rb...
<pre>
# Uses the same settings as net/ldap
AD_SETTINGS = {
	:host => 'domain-controller.example.local',
	:base => 'dc=example,dc=local',
	:port => 636,
	:encryption => :simple_tls,
	:auth => {
	  :method => :simple,
	  :username => "username",
	  :password => "password"
	}
}
</pre>

<h3>Simple finds using attributes</h3>
Then I put the base initialization in ../app/controllers/application_controller.rb...
<pre>
ActiveDirectory::Base.setup(settings)
</pre>

<p>Then in my model, or anywhere really, I can look for AD users, etc.</p>

<pre>
ActiveDirectory::User.find(:all)
ActiveDirectory::User.find(:first, :userprincipalname => "richard.navarrete@domain.com")

ActiveDirectory::Group.find(:all)

#Caching is disabled by default, to enable:
ActiveDirectory::Base.enable_cache
ActiveDirectory::Base.disable_cache
ActiveDirectory::Base.cache?
</pre>

<h3>ActiveRecord example</h3>
<p>You can also limit the fields that get returned, just like with ActiveRecord.</p>

<p>In ActiveRecord, you use ":select => ['select this', 'or', 'that']" - you can do this or use the net/ldap syntax of ":attributes => ..."  You should use one or the other, but not both.</p>

<pre>
ad_user = ActiveDirectory::User.find(:all, :attributes => ['givenname', 'sn'])

# if you don't give it an array and just one item, that's ok too...
ad_user = ActiveDirectory::User.find(:all, :attributes => 'givenname')

puts ad_user.givenname #=> Richard
puts ad_user.sn #=> Navarrete
puts ad_user.name #=> Richard Navarrete

# But looking for a field you didn't return will raise an ArgumentError.
puts ad_user.mail #=> ArgumentError: no id given
</pre>

<h3>Net::LDAP::Filter</h3>
You can pass any filter you can make in Net::LDAP::Filter along in the find.<br />
In this example, I have a couple of groups that a given user can be a member of.<br />
If they are a member of either of the groups (memberOf) then a user will be returned.<br />

<pre>
groups = ['CN=admins,OU=Security,OU=Groups,DC=Example,DC=Local', 'CN=HR,OU=Security,OU=Groups,DC=Example,DC=Local']

# Don't miss this important step -> be sure to put double quotes in the value, no matter if it's a
# single variable string that you're interpolating... it must be there or Net::LDAP::Filter will
# treat it like an Array and won't find gsub and error out!
filter = Net::LDAP::Filter.eq('distinguishedName', "#{session[:current_user][:dn]}")


# Same thing here with the memberOf equals... must have double quotes!
# Notice the |= under else, this will make the groups all OR conditions.
# Obviously replace this with &= if you require that the give user be 
# a member of ALL the given groups. 
right_filter = nil
groups.each do |group|
    if right_filter.nil?
        right_filter = Net::LDAP::Filter.eq('memberOf', "#{group}")
    else
        right_filter |= Net::LDAP::Filter.eq('memberOf', "#{group}")
    end
end

filter = filter & (right_filter)

# Assuming you already setup the Base, but just in case...
ActiveDirectory::Base.setup(AD_SETTINGS)

ad_user = ActiveDirectory::User.find(:all, filter)

</pre>

<h3>Updating thumbnailPhoto attribute in AD!</h3>
First, why would you want to do this?  I did it so that users could upload a photo in one place, and it would update other applications with user avatars where it was more convenient instead of making those applications point to a URL.  Basically, if you update thumbnailPhoto with an image, the user pic will show up for users in MS Outlook, MS Lync, etc.
Here is something I included in a user model (with email as an attribute), to update the coorsponding AD account with a thumbnailPhoto.
Use AD gem's "update_attribute."
<pre>
def update_ad_profile_pic
    begin
        ad_user = ActiveDirectory::User.find(:first, :mail => self.email)
        if ad_user.present?
            picture_data = image_to_bytes
            ad_user.update_attribute(:thumbnailPhoto, picture_data)
        else
            false
        end
    rescue Exception => e
        logger.error("** Failed updating AD photo for: #{self.email} \n#{e.message}")
    end
end

private

# convert this user's "image_tiny" byte-by-byte and return
# using Dragonfly here for the image, but you can use anything... it's just an image
def image_to_bytes
    picture_data = ""
    file = File.open("#{Rails.root}/public/#{self.image_tiny.remote_url}",'rb')
    file.read.each_byte do |byte|
        picture_data << byte
    end
    file.close
    picture_data
end
</pre>