fortinet_facts
---

*DISCLAIMER* This module is _not_ published to the forge and is explicitly _not_ under active maintenance from Puppet.

## Overview
Plan content for fetching and publishing fortinet device facts to the Connect application.

## Installation
To install this module to a Bolt project, add the following to the `modules` data in [bolt-project.yaml](https://puppet.com/docs/bolt/latest/bolt_project_reference.html):

```
modules:
  - git: git@github.com:puppetlabs/fortinet_facts.git
    ref: main
```

## Usage
The following usage examples use the Bolt CLI to show how the plan content in this module works. `forinet_facts::gather_facts` can (and should) also be run inside the Connect application with the same parameters provided through the Connect UI.

`fortinet_facts::generate_static_facts` _should only ever be run from the Bolt CLI, it will fail if run from the Connect application_. This plan is provided as a convenience for generating the static facts data usable by the gathering facts plan and is only ever meant to be executed with Bolt.

### Generating the static facts file
In order for the gather_facts operation to include facts from the bolt inventory.yaml file it reads static fact data from a file external to inventory.yaml. A convienence plan is available to generate this external file from Bolt: `fortinet_facts::generate_static_facts`. The generated file should be commited to the project so that the gather facts plan can read it from inside the Connect application.

Using the following example project structure (assume this project installs the `fortinet_facts` module using bolt-project.yaml):

```
my_project/
├── bolt-project.yaml
├── files/
├── inventory.yaml
├── plans/
│   └── my_plan.pp
└── tasks/
    ├── my_task.json
    └── my_task.sh
```

From the `my_project/files` directory on a workstation, run:

```
$ bolt plan run fortinet_facts::generate_static_facts
```

This will generate a file, `static_facts.yaml` inside the current directory `my_project/files`. The file should be committed to the project in the `files` directory location so that it will be available to plans inside the Connect application. The new project structure should look like:

```
my_project/
├── bolt-project.yaml
├── files/
│   └── static_facts.yaml
├── inventory.yaml
├── plans/
│   └── my_plan.pp
└── tasks/
    ├── my_task.json
    └── my_task.sh
```

Any time the `inventory.yaml` file is updated with new targets or facts: this operation should be repeated and the updated `static_facts.yaml` file should be committed.

### Running the gather facts operation
Once the `static_facts.yaml` file is committed to the project, you can run the `fortinet_facts::gather_facts` plan to actually gather facts from targets, merge them with any static facts, and publish them.

`fortinet_facts::gather_facts` includes a parameter called `dry_run` that causes the plan to run the gathering operations but stops before the publishing step. When the plan is run with `dry_run=true` it will not attempt any fact publish operations, and instead it will write out what it would have published for each target as the result of the plan. To run the plan as a "dry run":

```
$ bolt plan run fortinet_facts::gather_facts --target example-target.com static_facts_file="my_project/static_facts.yaml" dry_run=true
```

This should run the gathering operation and output the facts it would have published for the target `example-target.com`. Here's what each parameter to the plan does:
* `--target example-target.com` fills in the `$targets` param to the plan for which targets to gather facts for
* `static_facts_file="my_project/static_facts.yaml"` identifies the location of the static facts YAML data (committed earlier during the [Generating the static facts file](#generating-the-static-facts-file) section). More details on this parameter and the format of the value are available if you run `bolt plan show fortinet_facts::gather_facts`
* `dry_run=true` changes the behavior of the plan so that it does not perform the publish operation

Once you are ready to actually publish facts: simply set the `dry_run` parameter to `false` when running inside the Connect app to have the plan actually publish the gathered facts. *NOTE*: Running `fortinet_facts::gather_facts` from Bolt with `dry_run=false` will _not_ publish any facts to Connect, you _must_ run this plan from within Connect to actually publish anything.