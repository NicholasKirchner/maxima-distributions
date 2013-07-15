What this is
============

This is an attempt to extend Maxima to handle Laplace Transforms of expressions involving Dirac Delta, Heaviside, and unit doublet functionals.

Goals
-----

- [X] Maxima should compute the functionals at points where it makes sense.
- [X] Maxima should take symbolic derivatives of expressions involving these functionals.
- [X] Maxima should compute Laplace Transforms of expressions involving these functionals, especially where such expressions might appear in an introductory differential equations course.
- [X] Maxima should compute definite integrals involving these functionals.
- [] Maxima should compute indefinite integrals involving these functionals.
- [] Maxima should compute Inverse Laplace Transforms where the result involves these functionals, especially where such might be exercises in an introductory differential equations course.

To use
------

Put these files into your `~/.maxima` directory, run Maxima, and type
`load("file.lisp")` for each lisp file in the directory.
