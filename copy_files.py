import os

# ==========================================
# CONFIGURATION
# ==========================================
SEARCH_DIR = "."
OUTPUT_FILE = "mesh_messenger_code.ccco"
MODE = "both"  # "some" | "all" | "both"
# MODE = "some"

# List of EXACT filenames (used in "some" mode)
TARGET_FILES = [
    "AndroidManifest.xml",
    "pubspec.yaml",
    # "build.gradle.kts",
    # "settings.gradle.kts",
    # "proguard-rules.pro",
    # "gradle.properties",
]

# Settings for "all" / "both" modes
ALL_DIR = "lib"  # Folder to search for all files
ALLOWED_EXTENSIONS = [".dart"]
EXCLUDE_DIRS = ["node_modules", "__pycache__", ".git", "dist", "build"]
# ==========================================

def collect_some_files(search_path, output_path, target_files, outfile=None):
    """Mode 1: Collect some files by exact filename.
       If outfile is provided (file object), writes there instead of opening output_path."""
    targets = set(target_files)
    count = 0

    # Determine the file object to use
    if outfile is not None:
        f = outfile
        close_f = False
    else:
        f = open(output_path, "w", encoding="utf-8")
        close_f = True

    try:
        for root, dirs, files in os.walk(search_path):
            # Remove excluded directories from traversal
            dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]

            for filename in files:
                if filename in targets:
                    file_path = os.path.join(root, filename)

                    try:
                        with open(file_path, "r", encoding="utf-8") as infile:
                            content = infile.read()

                        clean_path = os.path.relpath(file_path, search_path)

                        f.write(f"FILE: {clean_path}\n")
                        f.write("```\n")
                        f.write(content)

                        if content and not content.endswith("\n"):
                            f.write("\n")

                        f.write("```\n\n")

                        print(f"Found and copied: {clean_path}")
                        count += 1

                    except UnicodeDecodeError:
                        print(f"SKIPPED (Not text): {file_path}")
                    except Exception as e:
                        print(f"ERROR reading {file_path}: {e}")

        if count == 0:
            print("\nNo matching files found. Check your spelling in TARGET_FILES.")
        else:
            print(f"\nSuccess! Processed {count}/{len(TARGET_FILES)} files into '{output_path}'.")

    except Exception as e:
        print(f"Critical Error: {e}")
    finally:
        if close_f:
            f.close()


def collect_all_by_extensions(folder_path, output_path, extensions, outfile=None):
    """Mode 2: Collect all files with specified extensions from a folder.
       If outfile is provided (file object), writes there instead of opening output_path."""
    count = 0
    collected_files = []

    if not os.path.exists(folder_path):
        print(f"Error: Folder '{folder_path}' does not exist.")
        return

    # Determine the file object to use
    if outfile is not None:
        f = outfile
        close_f = False
    else:
        f = open(output_path, "w", encoding="utf-8")
        close_f = True

    try:
        for root, dirs, files in os.walk(folder_path):
            # Remove excluded directories from traversal
            dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]

            for filename in files:
                # Check if file has one of the allowed extensions
                if any(filename.endswith(ext) for ext in extensions):
                    file_path = os.path.join(root, filename)
                    collected_files.append(file_path)

                    try:
                        with open(file_path, "r", encoding="utf-8") as infile:
                            content = infile.read()

                        clean_path = os.path.relpath(file_path, ".")

                        f.write(f"FILE: {clean_path}\n")
                        f.write("```\n")
                        f.write(content)

                        if content and not content.endswith("\n"):
                            f.write("\n")

                        f.write("```\n\n")

                        print(f"Found and copied: {clean_path}")
                        count += 1

                    except UnicodeDecodeError:
                        print(f"SKIPPED (Not text): {file_path}")
                    except Exception as e:
                        print(f"ERROR reading {file_path}: {e}")

        if count == 0:
            print(f"\nNo files found with extensions: {', '.join(extensions)}")
        else:
            print(f"\nSuccess! Processed {count} files from '{folder_path}' into '{output_path}'.")
            print(f"Extensions collected: {', '.join(extensions)}")

    except Exception as e:
        print(f"Critical Error: {e}")
    finally:
        if close_f:
            f.close()


def collect_files():
    """Main function to collect files based on selected mode"""
    print(f"Mode: {MODE}")
    print("-" * 50)

    if MODE == "some":
        collect_some_files(SEARCH_DIR, OUTPUT_FILE, TARGET_FILES)
    elif MODE == "all":
        folder_path = os.path.join(SEARCH_DIR, ALL_DIR)
        collect_all_by_extensions(folder_path, OUTPUT_FILE, ALLOWED_EXTENSIONS)
    elif MODE == "both":
        folder_path = os.path.join(SEARCH_DIR, ALL_DIR)
        with open(OUTPUT_FILE, "w", encoding="utf-8") as outfile:
            collect_some_files(SEARCH_DIR, OUTPUT_FILE, TARGET_FILES, outfile=outfile)
            collect_all_by_extensions(folder_path, OUTPUT_FILE, ALLOWED_EXTENSIONS, outfile=outfile)
        print("\nBoth modes combined into a single file.")
    else:
        print(f"Error: Unknown MODE '{MODE}'. Use 'some', 'all', or 'both'.")


if __name__ == "__main__":
    collect_files()
