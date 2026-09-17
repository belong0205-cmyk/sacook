# SA Cook Assistant 5.38

- Prioritises `stock`, `stocks`, `stockpot`, and common stock names in Apple Speech's limited vocabulary list.
- Corrects the observed `stuff` to `stock` error only when the surrounding culinary phrase clearly refers to stock.
- Preserves legitimate phrases such as `stuff the chicken`, `stuffed chicken`, and `turkey stuffing`.
- Applies the same correction to both AUTO and SPACE transcripts before matching an answer.
