# @summary
#   Gather facts from Fortinet devices and publish them to PDB. Facts gathered
#   are based off `get sys performance status` and `get sys status` commands
#
# @param targets [TargetSpec] The targets to gather facts for
#
# @param static_facts_file [String]
#   file to read static facts from. Filename should be in the form
#   modulename/filename, and the file should be located inside a module
#   per instructions in this doc:
#   https://puppet.com/docs/pe/2019.8/plans_limitations.html#script-and-file-sources
#
#   fortinet_facts::generate_static_facts is available to produce the
#   static facts file based on data from an inventory.yaml file
#
# @param dry_run [Boolean]
#   When set to true, the plan returns the hash of gathered facts and
#   does not publish any facts.
#
plan fortinet_facts::gather_facts (
  TargetSpec $targets,
  String     $static_facts_file = undef,
  Boolean    $dry_run = false
) {
  # Actually run the commands on all fortinet devices. The following HEREDOC
  # string is sent as a command to all targets
  $fortinet_command = @(COMMAND)
get sys performance status
get sys status
| COMMAND
  $command_result = run_command($fortinet_command, $targets)

  if $static_facts_file {
    # Read and parse all statically defined facts from the static_facts.yaml
    # file in to a hash.
    $static_facts = parseyaml(file::read($static_facts_file))
  }
  # Parse the output data from the run_command operation in to a format
  # readable as a set of facts.
  #
  # The following uses `map` to iterate over the target results and parse
  # successful results in to structure readable as a set of facts. The `map`
  # operation will return each processed result combined in an array.
  $all_target_facts = $command_result.map |$target_result| {
    $target_name = String($target_result.target.name)
    if $target_result.ok() {
      # Take the raw output from the commands run on the target and ensure
      # they are formatted as a string.
      $raw_output = String($target_result.value()['stdout'])
      # Pull the static facts for this target form the static_facts hash
      $target_static_facts = $static_facts[$target_name]['facts']
      # Parse the output from the run_command operation in to a hash of
      # key value pairs. These will become facts. The sys_output_to_hash
      # function is defined in:
      # fortinet_facts/lib/puppet/functions/sys_output_to_hash.rb
      $target_facts = sys_output_to_hash($raw_output)
      # Create a result hash formatted for use with the puppetdb_command
      # action performed later. The format for this hash is defined by the
      # API called to actually publish these facts.
      #
      # Values for 'environment', 'producer_timestamp', and 'producer' are
      # all defaults that need to be provided for the API to work, but
      # generally aren't useful in the context of Connect. All three values
      # are set for us always and shouldn't be modified.
      #
      # Values for 'certname' and 'values' are the important pieces of data
      # for this facts gathering operation:
      #   * 'certname' is what identifies the target that will have facts
      #      updated in the database.
      #   * 'values' are the fact values that will be published in to the
      #     database.
      $result = {
        'certname' => $target_name,
        'environment' => 'production',
        'producer_timestamp' => "${Timestamp.new().strftime('%Y-%m-%dT%H:%M:%S%:z')}",
        'producer' => 'connect',
        # The actual facts set for each target will be a merged hash of
        # both the static and dynamically generated facts
        'values' => $target_static_facts + $target_facts
      }
      # Finally, actually return the result hash to the `map` operation.
      $result
    }
    # If the result was a failure (i.e. if $target_result.ok() returns
    # false) we do nothing. Facts will not be updated for any target
    # that fails the run_command operation above.
  }
  if $dry_run {
    return $all_target_facts
  } else {
    # Iterate over all target facts collected and publish
    # them to the DB using puppetdb_command
    $all_target_facts.each |$target_fact_payload| {
      puppetdb_command('replace_facts', 5, $target_fact_payload)
    }
  }
}
