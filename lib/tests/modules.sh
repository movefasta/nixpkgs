#!/usr/bin/env bash

# This script is used to test that the module system is working as expected.
# Executing it runs tests for `lib.modules`, `lib.options` and `lib.types`.
# By default it test the version of nixpkgs which is defined in the NIX_PATH.
#
# Run:
# [nixpkgs]$ lib/tests/modules.sh
# or:
# [nixpkgs]$ nix-build lib/tests/release.nix

set -o errexit -o noclobber -o nounset -o pipefail
shopt -s failglob inherit_errexit

# https://stackoverflow.com/a/246128/6605742
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

cd "$DIR"/modules

pass=0
fail=0

evalConfig() {
    local attr=$1
    shift
    local script="import ./default.nix { modules = [ $* ];}"
    nix-instantiate --timeout 1 -E "$script" -A "$attr" --eval-only --show-trace --read-write-mode
}

reportFailure() {
    local attr=$1
    shift
    local script="import ./default.nix { modules = [ $* ];}"
    echo 2>&1 "$ nix-instantiate -E '$script' -A '$attr' --eval-only"
    evalConfig "$attr" "$@" || true
    ((++fail))
}

checkConfigOutput() {
    local outputContains=$1
    shift
    if evalConfig "$@" 2>/dev/null | grep -E --silent "$outputContains" ; then
        ((++pass))
    else
        echo 2>&1 "error: Expected result matching '$outputContains', while evaluating"
        reportFailure "$@"
    fi
}

checkConfigError() {
    local errorContains=$1
    local err=""
    shift
    if err="$(evalConfig "$@" 2>&1 >/dev/null)"; then
        echo 2>&1 "error: Expected error code, got exit code 0, while evaluating"
        reportFailure "$@"
    else
        if echo "$err" | grep -zP --silent "$errorContains" ; then
            ((++pass))
        else
            echo 2>&1 "error: Expected error matching '$errorContains', while evaluating"
            reportFailure "$@"
        fi
    fi
}

# Shorthand meta attribute does not duplicate the config
checkConfigOutput '^"one two"$' config.result ./shorthand-meta.nix

checkConfigOutput '^true$' config.result ./test-mergeAttrDefinitionsWithPrio.nix

# Check that a module argument is passed, also when a default is available
# (but not needed)
#
# When the default is needed, we currently fail to do what the users expect, as
# we pass our own argument anyway, even if it *turns out* not to exist.
#
# The reason for this is that we don't know at invocation time what is in the
# _module.args option. That value is only available *after* all modules have been
# invoked.
#
# Hypothetically, Nix could help support this by giving access to the default
# values, through a new built-in function.
# However the default values are allowed to depend on other arguments, so those
# would have to be passed in somehow, making this not just a getter but
# something more complicated.
#
# At that point we have to wonder whether the extra complexity is worth the cost.
# Another - subjective - reason not to support it is that default values
# contradict the notion that an option has a single value, where _module.args
# is the option.
checkConfigOutput '^true$' config.result ./module-argument-default.nix

# types.pathInStore
checkConfigOutput '".*/store/0lz9p8xhf89kb1c1kk6jxrzskaiygnlh-bash-5.2-p15.drv"' config.pathInStore.ok1 ./types.nix
checkConfigOutput '".*/store/0fb3ykw9r5hpayd05sr0cizwadzq1d8q-bash-5.2-p15"' config.pathInStore.ok2 ./types.nix
checkConfigOutput '".*/store/0fb3ykw9r5hpayd05sr0cizwadzq1d8q-bash-5.2-p15/bin/bash"' config.pathInStore.ok3 ./types.nix
checkConfigError 'A definition for option .* is not of type .path in the Nix store.. Definition values:\n\s*- In .*: ""' config.pathInStore.bad1 ./types.nix
checkConfigError 'A definition for option .* is not of type .path in the Nix store.. Definition values:\n\s*- In .*: ".*/store"' config.pathInStore.bad2 ./types.nix
checkConfigError 'A definition for option .* is not of type .path in the Nix store.. Definition values:\n\s*- In .*: ".*/store/"' config.pathInStore.bad3 ./types.nix
checkConfigError 'A definition for option .* is not of type .path in the Nix store.. Definition values:\n\s*- In .*: ".*/store/.links"' config.pathInStore.bad4 ./types.nix
checkConfigError 'A definition for option .* is not of type .path in the Nix store.. Definition values:\n\s*- In .*: "/foo/bar"' config.pathInStore.bad5 ./types.nix

# Check boolean option.
checkConfigOutput '^false$' config.enable ./declare-enable.nix
checkConfigError 'The option .* does not exist. Definition values:\n\s*- In .*: true' config.enable ./define-enable.nix
checkConfigError 'The option .* does not exist. Definition values:\n\s*- In .*' config.enable ./define-enable-throw.nix
checkConfigError 'while evaluating a definition from `.*/define-enable-abort.nix' config.enable ./define-enable-abort.nix
checkConfigError 'while evaluating the error message for definitions for .enable., which is an option that does not exist' config.enable ./define-enable-abort.nix

checkConfigOutput '^1$' config.bare-submodule.nested ./declare-bare-submodule.nix ./declare-bare-submodule-nested-option.nix
checkConfigOutput '^2$' config.bare-submodule.deep ./declare-bare-submodule.nix ./declare-bare-submodule-deep-option.nix
checkConfigOutput '^42$' config.bare-submodule.nested ./declare-bare-submodule.nix ./declare-bare-submodule-nested-option.nix ./declare-bare-submodule-deep-option.nix ./define-bare-submodule-values.nix
checkConfigOutput '^420$' config.bare-submodule.deep ./declare-bare-submodule.nix ./declare-bare-submodule-nested-option.nix ./declare-bare-submodule-deep-option.nix ./define-bare-submodule-values.nix
checkConfigOutput '^2$' config.bare-submodule.deep ./declare-bare-submodule.nix ./declare-bare-submodule-deep-option.nix ./define-shorthandOnlyDefinesConfig-true.nix
checkConfigError 'The option .bare-submodule.deep. in .*/declare-bare-submodule-deep-option.nix. is already declared in .*/declare-bare-submodule-deep-option-duplicate.nix' config.bare-submodule.deep ./declare-bare-submodule.nix ./declare-bare-submodule-deep-option.nix  ./declare-bare-submodule-deep-option-duplicate.nix

# Check integer types.
# unsigned
checkConfigOutput '^42$' config.value ./declare-int-unsigned-value.nix ./define-value-int-positive.nix
checkConfigError 'A definition for option .* is not of type.*unsigned integer.*. Definition values:\n\s*- In .*: -23' config.value ./declare-int-unsigned-value.nix ./define-value-int-negative.nix
# positive
checkConfigError 'A definition for option .* is not of type.*positive integer.*. Definition values:\n\s*- In .*: 0' config.value ./declare-int-positive-value.nix ./define-value-int-zero.nix
# between
checkConfigOutput '^42$' config.value ./declare-int-between-value.nix ./define-value-int-positive.nix
checkConfigError 'A definition for option .* is not of type.*between.*-21 and 43.*inclusive.*. Definition values:\n\s*- In .*: -23' config.value ./declare-int-between-value.nix ./define-value-int-negative.nix

# Check either types
# types.either
checkConfigOutput '^42$' config.value ./declare-either.nix ./define-value-int-positive.nix
checkConfigOutput '^"24"$' config.value ./declare-either.nix ./define-value-string.nix
# types.oneOf
checkConfigOutput '^42$' config.value ./declare-oneOf.nix ./define-value-int-positive.nix
checkConfigOutput '^\[ \]$' config.value ./declare-oneOf.nix ./define-value-list.nix
checkConfigOutput '^"24"$' config.value ./declare-oneOf.nix ./define-value-string.nix

# Check mkForce without submodules.
set -- config.enable ./declare-enable.nix ./define-enable.nix
checkConfigOutput '^true$' "$@"
checkConfigOutput '^false$' "$@" ./define-force-enable.nix
checkConfigOutput '^false$' "$@" ./define-enable-force.nix

# Check mkForce with option and submodules.
checkConfigError 'attribute .*foo.* .* not found' config.attrsOfSub.foo.enable ./declare-attrsOfSub-any-enable.nix
checkConfigOutput '^false$' config.attrsOfSub.foo.enable ./declare-attrsOfSub-any-enable.nix ./define-attrsOfSub-foo.nix
set -- config.attrsOfSub.foo.enable ./declare-attrsOfSub-any-enable.nix ./define-attrsOfSub-foo-enable.nix
checkConfigOutput '^true$' "$@"
checkConfigOutput '^false$' "$@" ./define-force-attrsOfSub-foo-enable.nix
checkConfigOutput '^false$' "$@" ./define-attrsOfSub-force-foo-enable.nix
checkConfigOutput '^false$' "$@" ./define-attrsOfSub-foo-force-enable.nix
checkConfigOutput '^false$' "$@" ./define-attrsOfSub-foo-enable-force.nix

# Check overriding effect of mkForce on submodule definitions.
checkConfigError 'attribute .*bar.* .* not found' config.attrsOfSub.bar.enable ./declare-attrsOfSub-any-enable.nix ./define-attrsOfSub-foo.nix
checkConfigOutput '^false$' config.attrsOfSub.bar.enable ./declare-attrsOfSub-any-enable.nix ./define-attrsOfSub-foo.nix ./define-attrsOfSub-bar.nix
set -- config.attrsOfSub.bar.enable ./declare-attrsOfSub-any-enable.nix ./define-attrsOfSub-foo.nix ./define-attrsOfSub-bar-enable.nix
checkConfigOutput '^true$' "$@"
checkConfigError 'attribute .*bar.* .* not found' "$@" ./define-force-attrsOfSub-foo-enable.nix
checkConfigError 'attribute .*bar.* .* not found' "$@" ./define-attrsOfSub-force-foo-enable.nix
checkConfigOutput '^true$' "$@" ./define-attrsOfSub-foo-force-enable.nix
checkConfigOutput '^true$' "$@" ./define-attrsOfSub-foo-enable-force.nix

# Check mkIf with submodules.
checkConfigError 'attribute .*foo.* .* not found' config.attrsOfSub.foo.enable ./declare-enable.nix ./declare-attrsOfSub-any-enable.nix
set -- config.attrsOfSub.foo.enable ./declare-enable.nix ./declare-attrsOfSub-any-enable.nix
checkConfigError 'attribute .*foo.* .* not found' "$@" ./define-if-attrsOfSub-foo-enable.nix
checkConfigError 'attribute .*foo.* .* not found' "$@" ./define-attrsOfSub-if-foo-enable.nix
checkConfigError 'attribute .*foo.* .* not found' "$@" ./define-attrsOfSub-foo-if-enable.nix
checkConfigOutput '^false$' "$@" ./define-attrsOfSub-foo-enable-if.nix
checkConfigOutput '^true$' "$@" ./define-enable.nix ./define-if-attrsOfSub-foo-enable.nix
checkConfigOutput '^true$' "$@" ./define-enable.nix ./define-attrsOfSub-if-foo-enable.nix
checkConfigOutput '^true$' "$@" ./define-enable.nix ./define-attrsOfSub-foo-if-enable.nix
checkConfigOutput '^true$' "$@" ./define-enable.nix ./define-attrsOfSub-foo-enable-if.nix

# Check disabledModules with config definitions and option declarations.
set -- config.enable ./define-enable.nix ./declare-enable.nix
checkConfigOutput '^true$' "$@"
checkConfigOutput '^false$' "$@" ./disable-define-enable.nix
checkConfigOutput '^false$' "$@" ./disable-define-enable-string-path.nix
checkConfigError "The option .*enable.* does not exist. Definition values:\n\s*- In .*: true" "$@" ./disable-declare-enable.nix
checkConfigError "attribute .*enable.* in selection path .*config.enable.* not found" "$@" ./disable-define-enable.nix ./disable-declare-enable.nix
checkConfigError "attribute .*enable.* in selection path .*config.enable.* not found" "$@" ./disable-enable-modules.nix

checkConfigOutput '^true$' 'config.positive.enable' ./disable-module-with-key.nix
checkConfigOutput '^false$' 'config.negative.enable' ./disable-module-with-key.nix
checkConfigError 'Module ..*disable-module-bad-key.nix. contains a disabledModules item that is an attribute set, presumably a module, that does not have a .key. attribute. .*' 'config.enable' ./disable-module-bad-key.nix

# Not sure if we want to keep supporting module keys that aren't strings, paths or v?key, but we shouldn't remove support accidentally.
checkConfigOutput '^true$' 'config.positive.enable' ./disable-module-with-toString-key.nix
checkConfigOutput '^false$' 'config.negative.enable' ./disable-module-with-toString-key.nix

# Check _module.args.
set -- config.enable ./declare-enable.nix ./define-enable-with-custom-arg.nix
checkConfigError 'while evaluating the module argument .*custom.* in .*define-enable-with-custom-arg.nix.*:' "$@"
checkConfigOutput '^true$' "$@" ./define-_module-args-custom.nix

# Check that using _module.args on imports cause infinite recursions, with
# the proper error context.
set -- "$@" ./define-_module-args-custom.nix ./import-custom-arg.nix
checkConfigError 'while evaluating the module argument .*custom.* in .*import-custom-arg.nix.*:' "$@"
checkConfigError 'infinite recursion encountered' "$@"

# Check _module.check.
set -- config.enable ./declare-enable.nix ./define-enable.nix ./define-attrsOfSub-foo.nix
checkConfigError 'The option .* does not exist. Definition values:\n\s*- In .*' "$@"
checkConfigOutput '^true$' "$@" ./define-module-check.nix

# Check coerced value.
set --
checkConfigOutput '^"42"$' config.value ./declare-coerced-value.nix
checkConfigOutput '^"24"$' config.value ./declare-coerced-value.nix ./define-value-string.nix
checkConfigError 'A definition for option .* is not.*string or signed integer convertible to it.*. Definition values:\n\s*- In .*: \[ \]' config.value ./declare-coerced-value.nix ./define-value-list.nix

# Check coerced value with unsound coercion
checkConfigOutput '^12$' config.value ./declare-coerced-value-unsound.nix
checkConfigError 'A definition for option .* is not of type .*. Definition values:\n\s*- In .*: "1000"' config.value ./declare-coerced-value-unsound.nix ./define-value-string-bigint.nix
checkConfigError 'toInt: Could not convert .* to int' config.value ./declare-coerced-value-unsound.nix ./define-value-string-arbitrary.nix

# Check mkAliasOptionModule.
checkConfigOutput '^true$' config.enable ./alias-with-priority.nix
checkConfigOutput '^true$' config.enableAlias ./alias-with-priority.nix
checkConfigOutput '^false$' config.enable ./alias-with-priority-can-override.nix
checkConfigOutput '^false$' config.enableAlias ./alias-with-priority-can-override.nix

# Check mkPackageOption
checkConfigOutput '^"hello"$' config.package.pname ./declare-mkPackageOption.nix
checkConfigError 'The option .undefinedPackage. is used but not defined' config.undefinedPackage ./declare-mkPackageOption.nix
checkConfigOutput '^null$' config.nullablePackage ./declare-mkPackageOption.nix

# submoduleWith

## specialArgs should work
checkConfigOutput '^"foo"$' config.submodule.foo ./declare-submoduleWith-special.nix

## shorthandOnlyDefines config behaves as expected
checkConfigOutput '^true$' config.submodule.config ./declare-submoduleWith-shorthand.nix ./define-submoduleWith-shorthand.nix
checkConfigError 'is not of type `boolean' config.submodule.config ./declare-submoduleWith-shorthand.nix ./define-submoduleWith-noshorthand.nix
checkConfigError "In module ..*define-submoduleWith-shorthand.nix., you're trying to define a value of type \`bool'\n\s*rather than an attribute set for the option" config.submodule.config ./declare-submoduleWith-noshorthand.nix ./define-submoduleWith-shorthand.nix
checkConfigOutput '^true$' config.submodule.config ./declare-submoduleWith-noshorthand.nix ./define-submoduleWith-noshorthand.nix

## submoduleWith should merge all modules in one swoop
checkConfigOutput '^true$' config.submodule.inner ./declare-submoduleWith-modules.nix
checkConfigOutput '^true$' config.submodule.outer ./declare-submoduleWith-modules.nix
# Should also be able to evaluate the type name (which evaluates freeformType,
# which evaluates all the modules defined by the type)
checkConfigOutput '^"submodule"$' options.submodule.type.description ./declare-submoduleWith-modules.nix

## submodules can be declared using (evalModules {...}).type
checkConfigOutput '^true$' config.submodule.inner ./declare-submodule-via-evalModules.nix
checkConfigOutput '^true$' config.submodule.outer ./declare-submodule-via-evalModules.nix
# Should also be able to evaluate the type name (which evaluates freeformType,
# which evaluates all the modules defined by the type)
checkConfigOutput '^"submodule"$' options.submodule.type.description ./declare-submodule-via-evalModules.nix

## Paths should be allowed as values and work as expected
checkConfigOutput '^true$' config.submodule.enable ./declare-submoduleWith-path.nix

## deferredModule
# default module is merged into nodes.foo
checkConfigOutput '"beta"' config.nodes.foo.settingsDict.c ./deferred-module.nix
# errors from the default module are reported with accurate location
checkConfigError 'In `the-file-that-contains-the-bad-config.nix, via option default'\'': "bogus"' config.nodes.foo.bottom ./deferred-module.nix
checkConfigError '.*lib/tests/modules/deferred-module-error.nix, via option deferred [(]:anon-1:anon-1:anon-1[)] does not look like a module.' config.result ./deferred-module-error.nix

# Check the file location information is propagated into submodules
checkConfigOutput the-file.nix config.submodule.internalFiles.0 ./submoduleFiles.nix


# Check that disabledModules works recursively and correctly
checkConfigOutput '^true$' config.enable ./disable-recursive/main.nix
checkConfigOutput '^true$' config.enable ./disable-recursive/{main.nix,disable-foo.nix}
checkConfigOutput '^true$' config.enable ./disable-recursive/{main.nix,disable-bar.nix}
checkConfigError 'The option .* does not exist. Definition values:\n\s*- In .*: true' config.enable ./disable-recursive/{main.nix,disable-foo.nix,disable-bar.nix}

# Check that imports can depend on derivations
checkConfigOutput '^true$' config.enable ./import-from-store.nix

# Check that configs can be conditional on option existence
checkConfigOutput '^true$' config.enable ./define-option-dependently.nix ./declare-enable.nix ./declare-int-positive-value.nix
checkConfigOutput '^360$' config.value ./define-option-dependently.nix ./declare-enable.nix ./declare-int-positive-value.nix
checkConfigOutput '^7$' config.value ./define-option-dependently.nix ./declare-int-positive-value.nix
checkConfigOutput '^true$' config.set.enable ./define-option-dependently-nested.nix ./declare-enable-nested.nix ./declare-int-positive-value-nested.nix
checkConfigOutput '^360$' config.set.value ./define-option-dependently-nested.nix ./declare-enable-nested.nix ./declare-int-positive-value-nested.nix
checkConfigOutput '^7$' config.set.value ./define-option-dependently-nested.nix ./declare-int-positive-value-nested.nix

# Check attrsOf and lazyAttrsOf. Only lazyAttrsOf should be lazy, and only
# attrsOf should work with conditional definitions
# In addition, lazyAttrsOf should honor an options emptyValue
checkConfigError "is not lazy" config.isLazy ./declare-attrsOf.nix ./attrsOf-lazy-check.nix
checkConfigOutput '^true$' config.isLazy ./declare-lazyAttrsOf.nix ./attrsOf-lazy-check.nix
checkConfigOutput '^true$' config.conditionalWorks ./declare-attrsOf.nix ./attrsOf-conditional-check.nix
checkConfigOutput '^false$' config.conditionalWorks ./declare-lazyAttrsOf.nix ./attrsOf-conditional-check.nix
checkConfigOutput '^"empty"$' config.value.foo ./declare-lazyAttrsOf.nix ./attrsOf-conditional-check.nix


# Even with multiple assignments, a type error should be thrown if any of them aren't valid
checkConfigError 'A definition for option .* is not of type .*' \
  config.value ./declare-int-unsigned-value.nix ./define-value-list.nix ./define-value-int-positive.nix

## Freeform modules
# Assigning without a declared option should work
checkConfigOutput '^"24"$' config.value ./freeform-attrsOf.nix ./define-value-string.nix
# Shorthand modules interpret `meta` and `class` as config items
checkConfigOutput '^true$' options._module.args.value.result ./freeform-attrsOf.nix ./define-freeform-keywords-shorthand.nix
# No freeform assignments shouldn't make it error
checkConfigOutput '^{ }$' config ./freeform-attrsOf.nix
# but only if the type matches
checkConfigError 'A definition for option .* is not of type .*' config.value ./freeform-attrsOf.nix ./define-value-list.nix
# and properties should be applied
checkConfigOutput '^"yes"$' config.value ./freeform-attrsOf.nix ./define-value-string-properties.nix
# Options should still be declarable, and be able to have a type that doesn't match the freeform type
checkConfigOutput '^false$' config.enable ./freeform-attrsOf.nix ./define-value-string.nix ./declare-enable.nix
checkConfigOutput '^"24"$' config.value ./freeform-attrsOf.nix ./define-value-string.nix ./declare-enable.nix
# and this should work too with nested values
checkConfigOutput '^false$' config.nest.foo ./freeform-attrsOf.nix ./freeform-nested.nix
checkConfigOutput '^"bar"$' config.nest.bar ./freeform-attrsOf.nix ./freeform-nested.nix
# Check whether a declared option can depend on an freeform-typed one
checkConfigOutput '^null$' config.foo ./freeform-attrsOf.nix ./freeform-str-dep-unstr.nix
checkConfigOutput '^"24"$' config.foo ./freeform-attrsOf.nix ./freeform-str-dep-unstr.nix ./define-value-string.nix
# Check whether an freeform-typed value can depend on a declared option, this can only work with lazyAttrsOf
checkConfigError 'infinite recursion encountered' config.foo ./freeform-attrsOf.nix ./freeform-unstr-dep-str.nix
checkConfigError 'The option .* is used but not defined' config.foo ./freeform-lazyAttrsOf.nix ./freeform-unstr-dep-str.nix
checkConfigOutput '^"24"$' config.foo ./freeform-lazyAttrsOf.nix ./freeform-unstr-dep-str.nix ./define-value-string.nix
# submodules in freeformTypes should have their locations annotated
checkConfigOutput '/freeform-submodules.nix"$' config.fooDeclarations.0 ./freeform-submodules.nix
# freeformTypes can get merged using `types.type`, including submodules
checkConfigOutput '^10$' config.free.xxx.foo ./freeform-submodules.nix
checkConfigOutput '^10$' config.free.yyy.bar ./freeform-submodules.nix

## types.anything
# Check that attribute sets are merged recursively
checkConfigOutput '^null$' config.value.foo ./types-anything/nested-attrs.nix
checkConfigOutput '^null$' config.value.l1.foo ./types-anything/nested-attrs.nix
checkConfigOutput '^null$' config.value.l1.l2.foo ./types-anything/nested-attrs.nix
checkConfigOutput '^null$' config.value.l1.l2.l3.foo ./types-anything/nested-attrs.nix
# Attribute sets that are coercible to strings shouldn't be recursed into
checkConfigOutput '^"foo"$' config.value.outPath ./types-anything/attrs-coercible.nix
# Multiple lists aren't concatenated together
checkConfigError 'The option .* has conflicting definitions' config.value ./types-anything/lists.nix
# Check that all equalizable atoms can be used as long as all definitions are equal
checkConfigOutput '^0$' config.value.int ./types-anything/equal-atoms.nix
checkConfigOutput '^false$' config.value.bool ./types-anything/equal-atoms.nix
checkConfigOutput '^""$' config.value.string ./types-anything/equal-atoms.nix
checkConfigOutput '^/$' config.value.path ./types-anything/equal-atoms.nix
checkConfigOutput '^null$' config.value.null ./types-anything/equal-atoms.nix
checkConfigOutput '^0.1$' config.value.float ./types-anything/equal-atoms.nix
# Functions can't be merged together
checkConfigError "The option .value.multiple-lambdas.<function body>. has conflicting option types" config.applied.multiple-lambdas ./types-anything/functions.nix
checkConfigOutput '^<LAMBDA>$' config.value.single-lambda ./types-anything/functions.nix
checkConfigOutput '^null$' config.applied.merging-lambdas.x ./types-anything/functions.nix
checkConfigOutput '^null$' config.applied.merging-lambdas.y ./types-anything/functions.nix
# Check that all mk* modifiers are applied
checkConfigError 'attribute .* not found' config.value.mkiffalse ./types-anything/mk-mods.nix
checkConfigOutput '^{ }$' config.value.mkiftrue ./types-anything/mk-mods.nix
checkConfigOutput '^1$' config.value.mkdefault ./types-anything/mk-mods.nix
checkConfigOutput '^{ }$' config.value.mkmerge ./types-anything/mk-mods.nix
checkConfigOutput '^true$' config.value.mkbefore ./types-anything/mk-mods.nix
checkConfigOutput '^1$' config.value.nested.foo ./types-anything/mk-mods.nix
checkConfigOutput '^"baz"$' config.value.nested.bar.baz ./types-anything/mk-mods.nix

## types.functionTo
checkConfigOutput '^"input is input"$' config.result ./functionTo/trivial.nix
checkConfigOutput '^"a b"$' config.result ./functionTo/merging-list.nix
checkConfigError 'A definition for option .fun.<function body>. is not of type .string.. Definition values:\n\s*- In .*wrong-type.nix' config.result ./functionTo/wrong-type.nix
checkConfigOutput '^"b a"$' config.result ./functionTo/list-order.nix
checkConfigOutput '^"a c"$' config.result ./functionTo/merging-attrs.nix
checkConfigOutput '^"a bee"$' config.result ./functionTo/submodule-options.nix
checkConfigOutput '^"fun.<function body>.a fun.<function body>.b"$' config.optionsResult ./functionTo/submodule-options.nix

# moduleType
checkConfigOutput '^"a b"$' config.resultFoo ./declare-variants.nix ./define-variant.nix
checkConfigOutput '^"a b y z"$' config.resultFooBar ./declare-variants.nix ./define-variant.nix
checkConfigOutput '^"a b c"$' config.resultFooFoo ./declare-variants.nix ./define-variant.nix

## emptyValue's
checkConfigOutput "[ ]" config.list.a ./emptyValues.nix
checkConfigOutput "{ }" config.attrs.a ./emptyValues.nix
checkConfigOutput "null" config.null.a ./emptyValues.nix
checkConfigOutput "{ }" config.submodule.a ./emptyValues.nix
# These types don't have empty values
checkConfigError 'The option .int.a. is used but not defined' config.int.a ./emptyValues.nix
checkConfigError 'The option .nonEmptyList.a. is used but not defined' config.nonEmptyList.a ./emptyValues.nix

## types.raw
checkConfigOutput "{ foo = <CODE>; }" config.unprocessedNesting ./raw.nix
checkConfigOutput "10" config.processedToplevel ./raw.nix
checkConfigError "The option .multiple. is defined multiple times" config.multiple ./raw.nix
checkConfigOutput "bar" config.priorities ./raw.nix

## Option collision
checkConfigError \
  'The option .set. in module .*/declare-set.nix. would be a parent of the following options, but its type .attribute set of signed integer. does not support nested options.\n\s*- option[(]s[)] with prefix .set.enable. in module .*/declare-enable-nested.nix.' \
  config.set \
  ./declare-set.nix ./declare-enable-nested.nix

# Options: accidental use of an option-type instead of option (or other tagged type; unlikely)
checkConfigError 'In module .*/options-type-error-typical.nix: expected an option declaration at option path .result. but got an attribute set with type option-type' config.result ./options-type-error-typical.nix
checkConfigError 'In module .*/options-type-error-typical-nested.nix: expected an option declaration at option path .result.here. but got an attribute set with type option-type' config.result.here ./options-type-error-typical-nested.nix
checkConfigError 'In module .*/options-type-error-configuration.nix: expected an option declaration at option path .result. but got an attribute set with type configuration' config.result ./options-type-error-configuration.nix

# Check that that merging of option collisions doesn't depend on type being set
checkConfigError 'The option .group..*would be a parent of the following options, but its type .<no description>. does not support nested options.\n\s*- option.s. with prefix .group.enable..*' config.group.enable ./merge-typeless-option.nix

# Test that types.optionType merges types correctly
checkConfigOutput '^10$' config.theOption.int ./optionTypeMerging.nix
checkConfigOutput '^"hello"$' config.theOption.str ./optionTypeMerging.nix

# Test that types.optionType correctly annotates option locations
checkConfigError 'The option .theOption.nested. in .other.nix. is already declared in .optionTypeFile.nix.' config.theOption.nested ./optionTypeFile.nix

# Test that types.optionType leaves types untouched as long as they don't need to be merged
checkConfigOutput 'ok' config.freeformItems.foo.bar ./adhoc-freeformType-survives-type-merge.nix

# Anonymous submodules don't get nixed by import resolution/deduplication
# because of an `extendModules` bug, issue 168767.
checkConfigOutput '^1$' config.sub.specialisation.value ./extendModules-168767-imports.nix

# Class checks, evalModules
checkConfigOutput '^{ }$' config.ok.config ./class-check.nix
checkConfigOutput '"nixos"' config.ok.class ./class-check.nix
checkConfigError 'The module .*/module-class-is-darwin.nix was imported into nixos instead of darwin.' config.fail.config ./class-check.nix
checkConfigError 'The module foo.nix#darwinModules.default was imported into nixos instead of darwin.' config.fail-anon.config ./class-check.nix

# Class checks, submoduleWith
checkConfigOutput '^{ }$' config.sub.nixosOk ./class-check.nix
checkConfigError 'The module .*/module-class-is-darwin.nix was imported into nixos instead of darwin.' config.sub.nixosFail.config ./class-check.nix

# submoduleWith type merge with different class
checkConfigError 'A submoduleWith option is declared multiple times with conflicting class values "darwin" and "nixos".' config.sub.mergeFail.config ./class-check.nix

# _type check
checkConfigError 'Could not load a value as a module, because it is of type "flake", in file .*/module-imports-_type-check.nix' config.ok.config ./module-imports-_type-check.nix
checkConfigOutput '^true$' "$@" config.enable ./declare-enable.nix ./define-enable-with-top-level-mkIf.nix
checkConfigError 'Could not load a value as a module, because it is of type "configuration", in file .*/import-configuration.nix.*please only import the modules that make up the configuration.*' config ./import-configuration.nix

# doRename works when `warnings` does not exist.
checkConfigOutput '^1234$' config.c.d.e ./doRename-basic.nix
# doRename adds a warning.
checkConfigOutput '^"The option `a\.b. defined in `.*/doRename-warnings\.nix. has been renamed to `c\.d\.e.\."$' \
  config.result \
  ./doRename-warnings.nix

# Anonymous modules get deduplicated by key
checkConfigOutput '^"pear"$' config.once.raw ./merge-module-with-key.nix
checkConfigOutput '^"pear\\npear"$' config.twice.raw ./merge-module-with-key.nix

# Declaration positions
# Line should be present for direct options
checkConfigOutput '^10$' options.imported.line10.declarationPositions.0.line ./declaration-positions.nix
checkConfigOutput '/declaration-positions.nix"$' options.imported.line10.declarationPositions.0.file ./declaration-positions.nix
# Generated options may not have line numbers but they will at least get the
# right file
checkConfigOutput '/declaration-positions.nix"$' options.generated.line18.declarationPositions.0.file ./declaration-positions.nix
checkConfigOutput '^null$' options.generated.line18.declarationPositions.0.line ./declaration-positions.nix
# Submodules don't break it
checkConfigOutput '^39$' config.submoduleLine34.submodDeclLine39.0.line ./declaration-positions.nix
checkConfigOutput '/declaration-positions.nix"$' config.submoduleLine34.submodDeclLine39.0.file ./declaration-positions.nix
# New options under freeform submodules get collected into the parent submodule
# (consistent with .declarations behaviour, but weird; notably appears in system.build)
checkConfigOutput '^34|23$' options.submoduleLine34.declarationPositions.0.line ./declaration-positions.nix
checkConfigOutput '^34|23$' options.submoduleLine34.declarationPositions.1.line ./declaration-positions.nix
# nested options work
checkConfigOutput '^30$' options.nested.nestedLine30.declarationPositions.0.line ./declaration-positions.nix

cat <<EOF
====== module tests ======
$pass Pass
$fail Fail
EOF

if [ "$fail" -ne 0 ]; then
    exit 1
fi
exit 0
