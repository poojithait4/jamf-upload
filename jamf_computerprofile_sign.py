#!/usr/bin/env python3

"""
** Jamf Computer Configuration Profile Signing Script
   by G Pugh

This script can be used to sign a computer profile. It will look for a valid Apple Developer ID Application identity in the current keychain, or you can supply one via the command line.

If no output path is supplied, the outputted file will have the same name as the input file, but with .signed.mobileconfig as the suffix instead of .mobileconfig

Note that signed profiles cannot be uploaded via the Jamf API. Signed profiles must therefore be manually uploaded using the Jamf Pro GUI Admin Console

For usage, run jamf_computerprofile_sign.py --help
"""

import argparse
import os.path
import subprocess
import uuid


def find_developer_id(verbosity):
    proc = subprocess.Popen(
        ["security", "find-identity", "-p", "codesigning", "-v"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
    )
    (output, error) = proc.communicate()
    if output:
        if verbosity:
            print(output)
            print()
        developer = output.split(b'"')[1].decode("utf-8")
        return developer
    if error:
        if verbosity:
            print(error)
            print()


def sign_profile(unsigned_profile, developer_id, output_path, verbosity):
    """Sign a profile using a given developer id.
    You can usually find a valid codesigning identity by using the following command:
    security find-identity -p codesigning -v
    """
    if not output_path:
        output_path = unsigned_profile.replace(".mobileconfig", ".signed.mobileconfig")
    cmd = [
        "/usr/bin/security",
        "cms",
        "-S",
        "-N",
        developer_id,
        "-i",
        unsigned_profile,
        "-o",
        output_path,
    ]
    if verbosity:
        print(cmd)
        print()
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    sout, serr = proc.communicate()
    if verbosity:
        if sout:
            print(f"Output of signing command: {sout}")
            print()
        elif serr:
            print("Error: Profile was not signed:")
            print(serr)
            print()
    return output_path


def get_args():
    """Parse any command line arguments"""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "mobileconfig", nargs="+", help="Path to Configuration Profile mobileconfig",
    )
    parser.add_argument(
        "--output_path", default="", help="Output path for signed mobileconfig",
    )
    parser.add_argument(
        "--developer",
        default="",
        help="an Apple Developer ID with the rights to sign a Configuration Profile",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="count",
        default=0,
        help="print verbose output headers",
    )
    args = parser.parse_args()

    return args


def main():
    """Do the main thing here"""
    print(
        "\n** Configuration Profile signing script",
        "\n** WARNING: This is an experimental script! Using it may have "
        "unexpected results!",
        "\n",
    )
    print(
        "The first run of this script in a session will most likely trigger "
        "a keychain prompt.",
        "\n",
    )

    # parse the command line arguments
    args = get_args()
    verbosity = args.verbose

    developer = find_developer_id(verbosity)

    if "Developer ID Application" in developer:
        args.developer = developer

    # sign the profile if a developer ID is supplied
    if args.developer:
        print(
            f"Signing profile(s) using certificate for developer id '{args.developer}'."
        )
        n = 1
        for profile_path in args.mobileconfig:
            if n > 1 and args.output_path:
                args.output_path = args.output_path.replace(
                    ".mobileconfig", f".{n}.mobileconfig"
                )

            # write the template to temp file
            signed_profile = sign_profile(
                profile_path, args.developer, args.output_path, verbosity
            )
            print(f"Path to signed profile {n}: {signed_profile}")
            n = n + 1
    else:
        print("No Developer ID provided")

    print()


if __name__ == "__main__":
    main()