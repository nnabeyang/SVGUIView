Pod::Spec.new do |s|
  s.name         = "SVGUIView"
  s.version      = "0.8.0"
  s.summary      = "An UIView that displays a single SVG image in your interface."
  s.homepage     = "https://github.com/nnabeyang/SVGUIView"
  s.license               = { :type => "MIT", :file => "LICENSE" }
  s.author             = { "nnabeyang" => "nabeyang@gmail.com" }

  s.platform = :ios
  s.ios.deployment_target = "14.0"

  s.source       = { :git => "https://github.com/nnabeyang/SVGUIView.git", :tag => "#{s.version}" }
  s.source_files  = "Sources/**/*.swift"
  s.requires_arc = true
  s.swift_version = '5.8'
end
