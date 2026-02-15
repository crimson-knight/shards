# Compile-time script: walks src/assistant_versions/*/ and prints a Hash literal
# Invoked via {{ run("./build_assistant_versions") }} in assistant_versions.cr

# Recursively collect all files (including those in dot-directories)
def walk_files(dir : String) : Array(String)
  result = [] of String
  Dir.each_child(dir) do |entry|
    full = File.join(dir, entry)
    if File.directory?(full)
      result.concat(walk_files(full))
    elsif File.file?(full)
      result << full
    end
  end
  result
end

base = File.join(File.dirname(__FILE__), "assistant_versions")

# Collect version directories
version_dirs = [] of String
Dir.each_child(base) do |entry|
  full = File.join(base, entry)
  version_dirs << full if File.directory?(full)
end
version_dirs.sort!

print "{"
version_dirs.each_with_index do |version_dir, vi|
  version = File.basename(version_dir)
  print ", " if vi > 0
  print "#{version.inspect} => {"

  files = walk_files(version_dir).sort
  files.each_with_index do |file, fi|
    relative = file.sub(version_dir, "")
    # Ensure path starts with ./
    relative = ".#{relative}" unless relative.starts_with?("./")
    print ", " if fi > 0
    print "#{relative.inspect} => #{File.read(file).inspect}"
  end
  print "}"
end
print "}"
