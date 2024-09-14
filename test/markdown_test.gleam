import birdie
import gleamoire/markdown

pub fn heading_test() {
  "
# Heading 1
## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
###### Heading 6
"
  |> markdown.render
  |> birdie.snap("Should render markdown headings")
}

pub fn code_test() {
  "
This is `inline code`.
This is block code:
```gleam
pub fn main() {
  todo
}
```
"
  |> markdown.render
  |> birdie.snap("Should render markdown code")
}

pub fn block_quote_test() {
  "
> There are only two hard things in Computer Science:
> Cache invalidation, and naming things
>   - Phil Karlton
"
  |> markdown.render
  |> birdie.snap("Should render markdown quotes")
}

pub fn list_test() {
  "
Shopping list:

- Bananas
- Milk
- Pineapples
- Mango
- Beer
- Coffee

Recipe:

1. Mix two ingredients
2. Preheat the oven
3. Pour the batter
4. Enjoy!
"
  |> markdown.render
  |> birdie.snap("Should render markdown lists")
}

pub fn separator_test() {
  "
Horizontal break

---

Afterwards

Line break \\
Other line break  
End
"
  |> markdown.render
  |> birdie.snap("Should render markdown separators")
}

pub fn emphasis_test() {
  "
**Bold**
__Underline__
*Italic*
_Other italic_
~~Strikethrough~~

**__Bold and underline__**
~~*Strikethrough and italic*~~
"
  |> markdown.render
  |> birdie.snap("Should render markdown emphasis")
}

pub fn hyperlink_test() {
  "
[See my website](http://localhost:8080)!

![And an image](https://gleam.run/images/lucy/lucy.svg)
"
  |> markdown.render
  |> birdie.snap("Should render markdown hyperlinks and images")
}
