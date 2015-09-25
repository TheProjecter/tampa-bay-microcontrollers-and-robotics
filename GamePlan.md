# Introduction #

This describes how the code is organized to allow us to share code.

# Directory Structure #

The directory structure on your PC includes three independent root directories:

  1. Code that runs on your PC (the assumption is that this is Python code)
  1. Libraries for the microcontroller (the assumption, for now, is that these are written in C/C++)
  1. Programs for the microcontroller (the assumption, for now, is that these are written in C/C++)

Each of these three roots would have an independent hg repository on google code.

This would require a maximum of three terminal windows open if you're doing development at all three levels.  (But I doubt that you would need to mess with the PC code, see below).

## PC Code ##

This directory would look like:

  * your-name-for-the-PC-code-root-directory
    * google-repo
    * clone-1
    * clone-2

The internals of the repo are yet to be defined.

You would permanently place one of the repo clones on your Python path (usually best done with a yourname.pth file in the Python installation directory, rather than using the PYTHONPATH environment variable).

The code in this repo probably won't change much.  It will be a driver program that lets you communicate with your Arduino over USB (or XBee, or ???) that will read in code from the uController program area to extend it to do anything funky needed for that program.

## uController Libraries ##

This directory would look like:

  * your-name-for-the-uclib-directory
    * google-repo
    * clone-1
    * clone-2
      * makefile
      * `*.h` (copied to ../include by makefile)
      * `*.c` and `*.cpp` (compiled to `../<processor-family>/*.o` by makefile)
    * include
      * `*.h` (files from repo of most recently run make)
    * <processor family> (for example atmegaX8)
      * `*.o` files (from repo of most recently run make)
      * uclib.a (includes all `*.o` files)

So you could have a terminal window open in the clone-2 directory where you can edit library code and run make to compile it and make it available to your programs.

Not sure yet how the processor family is specified to make.  (Any ideas?)

## uController Programs ##

This directory would look like:

  * your-name-for-the-ucprograms-directory
    * google-repo
    * clone-1
    * clone-2
      * program-1
      * program-2
        * makefile
        * <source files>
        * <processor family> (for compiled program; e.g., atmegaX8)
          * `*.o`
          * program.hex
        * python (for any extensions to the python PC tool to run this program)
          * extension\_1.py
          * extension\_2.py

You could have a terminal window open in the program-2 directory where you can edit program code, edit python/extension\_1.py code, run make, and run the python terminal tool (which will automatically load the extensions in the python subdirectory).