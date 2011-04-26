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
	module FieldType
		class Timestamp
			AD_DIVISOR = 10_000_000     #:nodoc:
			AD_OFFSET  = 11_644_473_600 #:nodoc:

			#
			# Encodes a local Time object (or the number of seconds since January
			# 1, 1970) into a timestamp that the Active Directory server can
			# understand (number of 100 nanosecond time units since January 1, 1601)
			# 
			def self.encode(local_time)
				(local_time.to_i + AD_OFFSET) * AD_DIVISOR
			end

			#
			# Decodes an Active Directory timestamp (the number of 100 nanosecond time
			# units since January 1, 1601) into a Ruby Time object.
			#
			def self.decode(remote_time)
				Time.at( (remote_time.to_i / AD_DIVISOR) - AD_OFFSET )
			end
		end
	end
end
