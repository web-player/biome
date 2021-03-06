#!/bin/env bats
# vim: set autoindent noexpandtab tabstop=4 shiftwidth=4 :
# a quick note: this file uses tabs to ensure that <<-EOF will work properly. Please use tabs too!
load test_helper

# ----------------------------------------------------------------------------
# biome init
# ------------------------------------------------------------------------------

@test "biome init will initialize a new project" {
	INPUT="$(cat <<-EOF
	my_app
	FOO
	bar

	baz
	EOF)"

	echo "$INPUT" | $BIOME init
	$(cmp $HOME/.biome/my_app.sh <<-EOF
		# A file that contains environment variables for a project
		# Activate me with biome use my_app
		# add variables like export FOO="bar"
		# include other variables with source /path/to/more/vars
		export FOO="baz"
	EOF)
}
@test "biome init will fail with a Biomefile" {
	touch Biomefile

	run $BIOME init
	[ "$status" -eq 1 ]
}
@test "biome init will fail with a preexisting environment" {
	echo "name=my_app" > Biomefile
	mkdir -p $HOME/.biome
	touch $HOME/.biome/my_app.sh

	run $BIOME init
	[ "$status" -eq 1 ]
}

# ----------------------------------------------------------------------------
# biome
# ------------------------------------------------------------------------------

@test "biome will create the environment that's defined in the Biomefile" {
	cat <<-EOF > Biomefile
	name=my_app
	FOO=hello
	BAR=world
	BAZ=
	EOF

	INPUT="$(cat <<-EOF
	data

	more data
	EOF)"
	echo "$INPUT" | $BIOME

	chmod 700 $HOME/.biome/my_app.sh
	$(cmp $HOME/.biome/my_app.sh <<-EOF
		export FOO="data"
		export BAR="world"
		export FOO="more data"
	EOF)
}
@test "biome will append to an already existing environment" {
	# create Biomefile ane pre-initialized data
	cat <<-EOF > Biomefile
	name=my_app
	ALREADY_EXISTS=
	FOO=hello
	BAR=world
	BAZ=
	EOF
	mkdir -p $HOME/.biome
	cat <<-EOF > $HOME/.biome/my_app.sh
	export ALREADY_EXISTS="hello"
	EOF

	INPUT="$(cat <<-EOF
	data

	more data
	EOF)"
	echo "$INPUT" | $BIOME

	chmod 700 $HOME/.biome/my_app.sh
	$(cmp $HOME/.biome/my_app.sh <<-EOF
		export ALREADY_EXISTS="hello"
		export FOO="data"
		export BAR="world"
		export FOO="more data"
	EOF)
}

# ----------------------------------------------------------------------------
# biome rm
# ------------------------------------------------------------------------------

@test "biome rm will remove an environment" {
	# create Biomefile ane pre-initialized data
	cat <<-EOF > Biomefile
	name=my_app
	EOF
	mkdir -p $HOME/.biome
	cat <<-EOF > $HOME/.biome/my_app.sh
	export A_VARIABLE="value"
	EOF

	$BIOME rm

	# make sure the environment doesn't exist
	run cat $HOME/.biome/my_app.sh
	[[ "$status" == 1 ]]

	# but also that the Biomefile does exist
	[[ "$(cat Biomefile)" == "name=my_app" ]]
}
@test "biome rm won't delete a non-existant environment" {
	# create Biomefile ane pre-initialized data
	cat <<-EOF > Biomefile
	name=my_app
	EOF
	mkdir -p $HOME/.biome
	# no environment

	run $BIOME rm
	[[ "$status" == 1 ]]

	# but also that the Biomefile does exist
	[[ "$(cat Biomefile)" == "name=my_app" ]]
}
@test "biome rm won't delete a non-existant environment (no .biome folder)" {
	# create Biomefile ane pre-initialized data
	cat <<-EOF > Biomefile
	name=my_app
	EOF
	# no environment

	run $BIOME rm
	[[ "$status" == 1 ]]

	# but also that the Biomefile does exist
	[[ "$(cat Biomefile)" == "name=my_app" ]]
}

# ----------------------------------------------------------------------------
# biome use
# ------------------------------------------------------------------------------

@test "biome use will spawn a subshell with the correct environment vars set" {
	# create Biomefile ane pre-initialized data
	cat <<-EOF > Biomefile
	name=my_app
	EOF
	mkdir -p $HOME/.biome
	cat <<-EOF > $HOME/.biome/my_app.sh
	export A_VARIABLE="value"
	export ANOTHER="content with spaces"
	EOF

	# log all environment variables within the shell to ~/environment
	OLDSHELL="$SHELL"
	SHELL="bash -c 'env > $HOME/environment'"
	run $BIOME use # use run so the command will always run so the shell can be reset
	SHELL="$OLDSHELL"

	chmod 700 $HOME/.biome/my_app.sh
	# these variables should be set
	[[ "$(cat $HOME/environment | grep A_VARIABLE=value)" != "" ]] &&
	[[ "$(cat $HOME/environment | grep ANOTHER=content\ with\ spaces)" != "" ]] &&
	[[ "$(cat $HOME/environment | grep BIOME_SHELL=true)" != "" ]] &&
	[[ "$(cat $HOME/environment | grep BIOME_PROJECT=my_app)" != "" ]];
}

# ----------------------------------------------------------------------------
# biome help
# ------------------------------------------------------------------------------

@test "biome help will show help" {
	run $BIOME help
	[[ "$status" == 0 ]] &&
	[[ "${lines[0]}" = "usage: biome <command>" ]]
}

@test "biome will fail for an unknown command" {
	run $BIOME something-unknown
	[[ "$status" == 1 ]] &&
	[[ "${lines[0]}" = "Hmm, I don't know how to do that. Run biome help for assistance." ]]
}

# ----------------------------------------------------------------------------
# biome inject
# ----------------------------------------------------------------------------
@test "biome inject will update a biome session" {
	# create Biomefile ane pre-initialized data
	cat <<-EOF > Biomefile
	name=my_app
	EOF
	mkdir -p $HOME/.biome
	cat <<-EOF > $HOME/.biome/my_app.sh
	export FOO="bar"
	EOF

	# log all environment variables within the shell to ~/environment
	OLDSHELL="$SHELL"
	SHELL="bash -c 'env > $HOME/pre && echo \"export a=b\" >> $HOME/.biome/my_app.sh && . $BIOME inject && env > $HOME/post'"
	run $BIOME use # use run so the command will always run so the shell can be reset
	SHELL="$OLDSHELL"

	# these variables should be set
	# They need to be pinned to the front because the $SHELL also contains the variable declaration
	[[ "$(cat $HOME/pre | grep ^a=b)" == "" ]] && # should not be updated at start
	[[ "$(cat $HOME/post | grep ^a=b)" != "" ]];  # should be updated by the end
}


# ----------------------------------------------------------------------------
# Biomefile nesting
# (Make sure that Biome can find, for example, ../Biomefile)
# ----------------------------------------------------------------------------
@test "biome should be able to find a biomefile that is nested 1 level below the current cwd" {
	echo "name=my_app" > ../Biomefile
	mkdir -p $HOME/.biome
	touch $HOME/.biome/my_app.sh

	run $BIOME use my_app
	[ "$status" -eq 0 ]
	rm ../Biomefile
}
@test "biome should be able to find a biomefile that is nested multiple levels below the current cwd" {
	echo "name=my_app" > ../../Biomefile
	mkdir -p $HOME/.biome
	touch $HOME/.biome/my_app.sh

	run $BIOME use my_app
	[ "$status" -eq 0 ]
	rm ../../Biomefile
}
@test "biome fails when a biomefile does not exist at any level" {
	mkdir -p $HOME/.biome
	touch $HOME/.biome/my_app.sh

	run $BIOME use my_app
	[ "$status" -eq 1 ]
}



HOME="$OLDHOME"
