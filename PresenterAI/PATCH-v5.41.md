# SA Cook Assistant 5.41

- Improves cooking speech recognition with a high-priority culinary vocabulary, including `grill`, `grilled`, and `grilling`.
- Uses Apple Speech's alternative transcriptions and word alternatives to prefer terminology found in the SA Cook vocabulary.
- Corrects the observed `gorilla` / `guerrilla` confusion only in cooking contexts while preserving genuine non-cooking sentences.
- Applies the same corrected acoustic transcript independently to both AUTO and SPACE.
