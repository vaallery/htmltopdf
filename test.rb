require 'grover'

html = File.read( "filename.html" )
pdf = Grover.new(html.force_encoding('utf-8'), emulate_media: 'print').to_pdf
File.open('filename.pdf', 'wb') { |file| file << pdf }
