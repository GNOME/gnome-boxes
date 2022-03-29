# Coding guide

If you are interested in reporting an issue, read the section "Reporting Bugs"
in README.md.

This file is intended to help new developers to get started with developing
Boxes.

For additional resources, visit the [Boxes Developer Documentation](https://gitlab.gnome.org/GNOME/gnome-boxes/-/wikis/home).

## Contribution guidelines

* Follow our coding style.
* Include only the necessary changes in your commits.
* Read our [commit message guidelines](https://wiki.gnome.org/Git/CommitMessages).
* [Submit a merge-request](https://wiki.gnome.org/Newcomers/SubmitContribution).

## Contributing

 * Tasks that are good for new contributors are marked with the ["Newcomers" label](https://gitlab.gnome.org/GNOME/gnome-boxes/issues?label_name%5B%5D=4.+Newcomers).
 * [Building the project](https://wiki.gnome.org/Newcomers/BuildProject) from the source code.

## Learn more about Vala

 * [Documentation](https://wiki.gnome.org/Projects/Vala/Documentation)
 * [API docs](https://valadoc.org)

## Coding style

The coding style used in this project is similar to most Vala projects.
In particular, the following rules are largely adapted from the Rygel
Coding Style.

 * 4-spaces (and not tabs) for indentation.
 * 1-space between function name and braces (both calls and signature
   declarations).
 * Prefer lines of less than <= 120 columns.
 * Prefer `foreach` over `for`.
 * Prefer descriptive names over abbreviations (unless well-known).
 * Avoid the use of `this` keyword.
 * Avoid unnecessary comment blocks. Favor descriptive variable and method names.
 * Place each `class` should go in a separate `.vala` file and named according to
   the class in it. E.g `Boxes.SpiceDisplay` -> `spice-display.vala`.
 * Avoid putting more than 3 `using` statements in each .vala file. If
   you feel you need to use more, perhaps you should consider
   refactoring (Move some of the code to a separate class).
 * If function signature/call fits in a single line, do not break it
   into multiple lines.
 * Use `var` in variable declarations wherever possible.
 * Use `as` to cast wherever possible.
 * Single statements inside `if`/`else` must not be enclosed by `{}`.
 * Declare the namespace of the `class`/`errordomain` with the class itself.
   For example:

```vala
   private class Boxes.Hello {
   ...
   };
```
 * Add a newline to break the code in logical pieces
 * Add a newline before each `return`, `throw`, `break` etc. if it
   is not the only statement in that block

```vala
    if (condition_applies ()) {
      do_something ();

      return false;
    }

    if (other_condition_applies ())
      return true;
```

   Except for the break in a switch:

```vala
    switch (val) {
    case 1:
        debug ("case 1");
        do_one ();
        break;

    default:
        ...
    }
```

## Default branch renamed to main

The default development branch has been renamed to `main`. To update
your local checkout, use:

```
git checkout master
git branch -m master main
git fetch
git branch --unset-upstream
git branch -u origin/main
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
```
