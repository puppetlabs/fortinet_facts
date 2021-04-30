# Convert the output of fortiOS 'get sys' commands to a hash
# structure readable as a set of facts.
#
# This is a custom puppet function defined using puppet's
# custom ruby function API. See
# https://puppet.com/docs/puppet/7.5/functions_ruby_overview.html
# for detailed docs on custom ruby functions
Puppet::Functions.create_function(:'convert_to_fact_name') do
  # This dispatch definition is boilerplate for creating a
  # puppet language function. The definition here defines
  # what ruby function the puppet function will call and
  # the function signature (i.e. any parameters the function
  # takes). See:
  # https://puppet.com/docs/puppet/7.5/functions_ruby_signatures.html#writing-signatures-with-dispatch
  # for detailed docs on dispatch definitions
  dispatch :translate_to_fact_name do
    param 'String', :raw_string
  end

  # Translate any string in to a valid fact name, which
  # should be all lowercase and only include the characters
  # a-z and underscores.
  def translate_to_fact_name(raw_string)
    # The translation itself is done in three parts using core
    # ruby functions:
    #
    # * First, .strip will remove any whitespace at the beginning
    #   or ending of the string
    # * Second, .gsub will replace any character that is _not_
    #   either a letter or underscore in to an underscore. See
    #   https://ruby-doc.org/core-2.4.0/Regexp.html#class-Regexp-label-Character+Classes
    #   for detailed docs on the regex match for characters
    #   to be replaced: `\W` is a metacharacter that matches any
    #   character that is not a letter or underscore.
    # * Third, .downcase changes any capital letters to lowercase
    raw_string.strip.gsub(/\W/, '_').downcase
  rescue Exception => e
    # Capture _all_ exceptions from this operation and wrap them in
    # a Bolt::Error type which is thrown. We wrap all errors in this
    # type so that when plans use this function they can catch any
    # failures with catch_errors() (that function only catches the
    # Bolt::Error type).
    raise Bolt::Error.new(
      "failed to translate '#{raw_string}' to fact name: #{e.message}",
      'fact-name-translation-failure'
    )
  end
end