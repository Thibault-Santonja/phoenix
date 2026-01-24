# Dialyzer ignore patterns
# Note: Most warnings are false positives from Ecto macros and Phoenix LiveView

[
  # ProcessingStatus Value Object - intentional broader specs for future extensibility
  # The specs are correct supertypes that allow for future status/transition additions
  {"lib/portfolio/photography/value_objects/processing_status.ex", :contract_supertype}
]
