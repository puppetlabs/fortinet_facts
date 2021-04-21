# @summary
#   Generate the static_facts.yaml based on facts set in the bolt
#   inventory
plan fortinet_facts::generate_static_facts() {
  # Use .map to iterate over all targets in the bolt inventory and
  # produce an array of fact sets for each target
  $all_target_facts = get_targets('all').map |$target_data| {
    # The structure of this return value to the map operation is
    # somewhat strange: we return a nested array of the form:
    #
    #  [ <target name string>, { 'facts' => <hash of facts> } ]
    #
    #   for example:
    #
    #  [ 'target_name_string', { 'facts' => { 'fact_name' => 'fact_value' } } ]
    #
    # we do this to produce a format puppet can convert from an
    # array (which the result of this .map operation will be) to
    # a hash of the form:
    #
    # {
    #   'target_name' => {
    #     'facts' => <facts>
    #   },
    #   'another_target' => {
    #     'facts' => <other facts>
    #   }
    # }
    #
    # See: https://puppet.com/docs/puppet/7.5/typecasting.html#converting-data-structures
    # for more detailed docs on why this structure of arrays
    # produces the desired outcome.
    [ $target_data.name, { 'facts' => $target_data.facts } ]
  }
  # Convert the result of the above .map operation in to a
  # hash, then convert the hash to valid YAML and write the
  # YAML out to a file.
  file::write('./static_facts.yaml', to_yaml(Hash($all_target_facts)))
}
