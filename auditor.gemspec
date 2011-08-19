# Provide a simple gemspec so you can easily use your enginex
# project in your rails apps through git.
Gem::Specification.new do |s|
  s.name = "auditor"
  s.summary = "Simple Audit Plugin intended to audit changes to ActiveRecord Models."
  s.description = "see above."
  s.files = Dir["{app,lib,config}/**/*"] + ["MIT-LICENSE", "Rakefile", "Gemfile", "README.rdoc"]
  s.version = "0.3.0"
  s.authors = ['Thomas Heller']
end
