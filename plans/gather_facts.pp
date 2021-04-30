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
# @return [Hash]
#   A hash containing key/value data on any failures that occured processing
#   individual targets. Top-level keys in the hash are target names, and their
#   associated values are the failure that occured for that target.
#
#   If dry_run is set to true, the Hash also includes key/value data on what
#   the plan would have submitted as facts for all targets that succeeded.
#   The structure of successful key/value entries is similar: keys are target
#   names, and values contain the data that would have been submitted
#
#   If dry_run is false and all targets succeed: an empty hash is returned
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
  $command_result = run_command($fortinet_command, $targets, '_catch_errors' => true)

  if $static_facts_file {
    # Read and parse all statically defined facts from the static_facts.yaml
    # file in to a hash.
    $static_facts = parseyaml(file::read($static_facts_file))
  }
  # Parse the output data from the run_command operation in to a format
  # readable as a set of facts.
  #
  # The following uses `map` to iterate over the target results and parse
  # results in to structure readable as a set of facts. The `map` operation
  # will return each processed result combined in an array.
  #
  # When processing each individual result, values returned back to the
  # .map operation which are added to the $all_target_facts array are all
  # of the same form: [ target_name, value ] (an array of size two with
  # two values: the target name and the actual value). This means
  # $all_target_facts will be in the form
  #
  # [ [ target_name, value], [ another_target_name, another_value] ]
  #
  # We create this structure specifically so that we can turn the
  # $all_target_facts array in to a hash of the structure:
  #
  # { target_name => value, another_target_name => another_value }
  #
  # See: https://puppet.com/docs/puppet/7.5/typecasting.html#converting-data-structures
  # for more detailed docs on why that structure of arrays
  # produces the desired outcome of a Hash.
  $all_target_facts = $command_result.map |$target_result| {
    $target_name = String($target_result.target.name)
    # Check if the result of the run_command operation for this target
    # was successful. If it was not, it's processed differently below.
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
      $target_facts = catch_errors() || {
        sys_output_to_hash($raw_output)
      }
      if $target_facts =~ Error {
        # If the sys_output_to_hash translation fails (in this case when
        # the type for the target_facts var is Error): we don't fail the
        # entire plan but instead return the error to the map operation
        # to be included in the $all_target_facts array.
        #
        # Logic below will check for any Error results in the $all_target_facts
        # array and process the error differently from successful results
        [ $target_name, $target_facts ]
      } else {
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
        $result_hash = {
          'certname' => $target_name,
          'environment' => 'production',
          'producer_timestamp' => "${Timestamp.new().strftime('%Y-%m-%dT%H:%M:%S%:z')}",
          'producer' => 'connect',
          # The actual facts set for each target will be a merged hash of
          # both the static and dynamically generated facts
          'values' => $target_static_facts + $target_facts
        }
        # This $result_hash is sent back to the .map operation to be added to the
        # $all_target_facts array
        [ $target_name, $result_hash ]
      }
    } else {
      # This is where we process target results from the original run_command operation
      # that were not successful. Processing in this case is trivial: we just return the
      # error result itself back to the .map operation to be added to the $all_target_facts
      # array
      #
      # Logic below will check for any Error results in the $all_target_facts
      # array and process the error differently from successful results
      [ $target_name, $target_result.error() ]
    }
  }
  # If dry_run is set to true: return the $all_target_facts array translated in to a hash
  if $dry_run {
    return Hash($all_target_facts)
  } else {
    # Translate $all_target_facts to a hash (see comment about the first .map operation
    # for details on what this hash will look like) and then iterate over that hash
    # processing each result based on what type it is. Failures are returned to this
    # .map operation along with the target name for which the failure occured.
    #
    # Only failure results are returned to this .map operation, including both entries
    # in $all_target_facts that are already errors and any new errors that occur when
    # attempting the puppetdb_command operation is performed. $final_result can then be
    # translated to a hash that is either:
    #   * An empty hash if every part of this plan succeeded
    #   * A hash of key/value pairs where keys are target names and the values contain
    #     details of what error occured when processing that target
    $final_result = Hash($all_target_facts).map |$payload_target_name, $target_fact_payload| {
      if $target_fact_payload =~ Error {
        [ $payload_target_name, $target_fact_payload ]
      } else {
        # Catch any errors from attempting the puppetdb_command operation and return
        # them to the .map operation. If the operation succeeds, don't return anything
        # to the map operation (by default a value of 'undef' will get added if nothing
        # is returned directly to .map, these undef values are filtered out of the final
        # output below)
        $pdb_command_result = catch_errors() || {
          puppetdb_command('replace_facts', 5, $target_fact_payload)
        }
        if $pdb_command_result =~ Error {
          [ $payload_target_name, $pdb_command_result ]
        }
      }
    }
    # Filter out any array items that are undef (undef values are added to the
    # final_result array for targets that fully succeeded) and then translate
    # the result of that filtering in to a hash. The resulting hash should now
    # only contain key/value pairs of targetname/failure data for any failures
    # that occured during the plan. In the case where there are no failures,
    # the result will be an empty hash.
    #
    # Return the results of this final filter/translate operation as the result
    # of the plan
    return Hash($final_result.filter |$item| { $item != undef })
  }
}
