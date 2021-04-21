# Convert the output of fortiOS 'get sys' commands to a hash
# structure readable as a set of facts.
#
# This is a custom puppet function defined using puppet's
# custom ruby function API. See
# https://puppet.com/docs/puppet/7.5/functions_ruby_overview.html
# for detailed docs on custom ruby functions
Puppet::Functions.create_function(:'sys_output_to_hash') do
  # This dispatch definition is boilerplate for creating a
  # puppet language function. The definition here defines
  # what ruby function the puppet function will call and
  # the function signature (i.e. any parameters the function
  # takes). See:
  # https://puppet.com/docs/puppet/7.5/functions_ruby_signatures.html#writing-signatures-with-dispatch
  # for detailed docs on dispatch definitions
  dispatch :translate_sys_output do
    param 'String', :raw_output
  end

  # Translate the raw output string in to a hash
  def translate_sys_output(raw_output)
    translated_output = {}
    # Iterate over each line of the raw output and create a new
    # fact based on each.
    raw_output.each_line do |line|
      # The following will split the string on the first instance
      # of a colon and return an array such that a string like
      #    "Some String: Another string"
      # returns a hash like
      #    ["Some String", "Another string"]
      # The second parameter defines to the split function that it
      # will only ever return 2 strings max, forcing the function
      # to only ever split on the first colon in case there are
      # other colons in the string. For a string like:
      #   Some String: Another String: With another colon
      # will be parsed in to
      #    ["Some String", "Another String: With another colon"]
      split_line = line.split(':', 2)
      # Take the string _prior to_ the first colon as the fact name
      # and translate it to a valid fact name (see the convert_to_fact_name
      # function for details on that translation, located at
      # lib/puppet/functions/convert_to_fact_name.rb)
      fact_name = call_function('convert_to_fact_name', split_line[0])
      # Take the string _after_ the first colon as the value of the fact
      #  (.strip will ensure there's no whitespace at the
      #   beginning or end of the value)
      fact_value = split_line[1].strip
      translated_output[fact_name] = fact_value
    end
    translated_output
  end
end