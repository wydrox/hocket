# Native component map

| Purpose | SwiftUI component |
| --- | --- |
| Connection fields and inline feedback | Form, Section, TextField, SecureField, Label |
| Optional setup entry and server check | Labeled Button, ProgressView |
| Guided steps | Sheet containing NavigationStack and Form |
| Technical and Desktop details | DisclosureGroup |
| Back / close / continue | Native toolbar buttons and prominent Button |
| Open the entered HTTPS origin | Link |
| Larger text / iPad adaptation | Semantic text styles and native Form layout |

No new dependency, custom gesture, fixed screen size, or web component. The guide
reuses the connection form’s hierarchy and retains the platform’s dismissal.
