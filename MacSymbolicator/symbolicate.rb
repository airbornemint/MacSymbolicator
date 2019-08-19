crash_file = ARGV[0]
dsym_file = ARGV[1]
quiet = ARGV.include?('-q')

if (crash_file.nil? || dsym_file.nil?)
  puts 'Usage: ruby symbolicate.rb <crash_file> <dsym_file>'
  exit false
end

dsym_file = Dir["#{dsym_file}/Contents/Resources/DWARF/*"].first || dsym_file
crash_content = File.open(crash_file, 'r').read

# If this is a sample (rather than a crash report), delete some garbage that isn't used for symbolication and doesn't make the output any better
crash_content = crash_content.gsub(/\?\?\?\s+\(in\s+(.*)\)\s+load\s+address\s+(0x.*?\s+\+\s+0x.*?)\s+\[(0x.*?)(\].*)/, "\\1 \\3 \\2")

process_name = crash_content.scan(/^Process:\s+(.*?)\s\[/im).flatten.first
load_address, bundle_identifier = crash_content.scan(/Binary Images:.*?(0x.*?)\s.*?\+(.*?)\s\(/im).flatten
addresses = crash_content.scan(/^(?:\s+\+\s+)?\d+\s+(?:#{bundle_identifier}|#{process_name}).*?(0x.*?)\s/im).flatten
code_type = crash_content.scan(/^Code Type:(.*?)(?:\(.*\))?$/i).flatten.first.strip
code_type = code_type.gsub(/\s+/m, ' ').gsub(/^\s+|\s+$/m, '').split(" ").first.strip

code_types_to_arch = { 'X86-64' => 'x86_64', 'X86' => 'i386', 'PPC' => 'ppc' }
arch = code_types_to_arch[code_type] || code_type

unless quiet
  puts 'MacSymbolicator information:'
  puts '-'*10
  puts "Process: #{process_name}"
  puts "Bundle Identifier: #{bundle_identifier}"
  puts "Load address: #{load_address}"
  puts "Lookup addresses: #{addresses.join(', ')}"
  puts '-'*10
  puts
end

# No addresses to look up; no need to go any further because
# `atos` will enter interactive mode without these.
if addresses.empty?
  puts crash_content
  exit true
end

result = `xcrun atos -o \"#{dsym_file}\" -arch #{arch} -l #{load_address} #{addresses.join(' ')}`.strip

if (!result.empty?)
  lines = result.split("\n")

  if lines.count != addresses.count
    puts 'Unexpected error.'
    puts lines
    exit false
  else
    addresses.each_index {
      |index|
      symbol = lines[index]
      crash_content.gsub!(/#{addresses[index]}.*?$/i, "#{addresses[index]} #{symbol}")
    }

    puts crash_content

    exit true
  end
else
  puts "Couldn't continue because of atos error."
  exit false
end
