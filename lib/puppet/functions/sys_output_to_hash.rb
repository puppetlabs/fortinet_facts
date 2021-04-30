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
    # Begin the translation process by removing any instances
    # of the machine's prompt string. The prompt string appears
    # even when the session isn't interactive. A ruby function
    # below defines the behavior of removing the prompt string.
    output_no_prompt = remove_prompt_from_output(raw_output)
    # Iterate over each line of the raw output and create a new
    # fact based on each.
    output_no_prompt.each_line do |line|
      # If the line is empty, move on to the next line. The .strip
      # function ensures a line with some whitespace doesn't cause
      # .empty? to return false.
      if line.strip.empty?
        next
      end
      # The following will split the string on the first instance
      # of a colon and return an array such that a string like
      #    "Some String: Another string"
      # returns a hash like
      #    ["Some String", "Another string"]
      # The second parameter defines to the split function that it
      # will only ever return 2 strings max, forcing the function
      # to only ever split on the first colon in case there are
      # other colons in the string. In the case of a string like:
      #    "Some String: Another String: With another colon"
      # it will be parsed in to
      #    ["Some String", "Another String: With another colon"]
      split_line = line.split(':', 2)
      # Take the string _prior to_ the first colon as the fact name
      # and translate it to a valid fact name. The 'call_function'
      # method is a puppet functions helper that allows custom functions
      # to call other custom functions. See the convert_to_fact_name
      # function for details on the fact name translation, located at
      # lib/puppet/functions/convert_to_fact_name.rb
      fact_name = call_function('convert_to_fact_name', split_line[0])
      # Take the string _after_ the first colon as the value of the fact
      #  (.strip will ensure there's no whitespace at the
      #   beginning or end of the value)
      fact_value = split_line[1].strip
      # Finally, actually add the new fact to the translated output hash
      translated_output[fact_name] = fact_value
    end
    # Return the fully formed translated_output hash as the result
    # of this puppet function call
    translated_output
  rescue Exception => e
    # Capture _all_ exceptions from this operation and wrap them in
    # a Bolt::Error type which is thrown. We wrap all errors in this
    # type so that when plans use this function they can catch any
    # failures with catch_errors() (that function only catches the
    # Bolt::Error type).
    raise Bolt::Error.new(
      "Failed to translate raw output to facts: #{e.message}",
      'output-translation-failure'
    )
  end

  # Remove any machine prompt strings from the raw output, leaving
  # only the output from the commands
  def remove_prompt_from_output(raw_output)
    # First: figure out the prompt string by matching with the
    # first sub-string that:
    # 1. starts at the beginning of the raw output
    # 2. includes any number of chars
    # 3. ends with # or $
    #
    # Ruby's .match function does not return a value usable
    # by the .gsub function below, so we use .to_s to force
    # the output of this function in to a string
    prompt_string = raw_output.match(/^(.*)(\#|\$)/).to_s
    # Second: remove any instances of that prompt string. If
    # prompt_string is empty, that means the output does
    # not appear to have any prompts in it. In that case,
    # continue with raw_output unchanged
    if prompt_string.empty?
      return raw_output
    else
      # .gsub removes any instance of the first string argument
      # with the second string argument. In this case, remove
      # any instances of prompt_string with the empty string.
      return raw_output.gsub(prompt_string, '')
    end
  end
end