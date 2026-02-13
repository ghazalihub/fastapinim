import nimfastapi, json, asyncdispatch
import ../models/schemas

let router* = newAPIRouter()

router.get("/"):
  proc read_items(): seq[Item] =
    return @[
      Item(id: 1, title: "Foo", price: 42.0),
      Item(id: 2, title: "Bar", price: 32.0, description: some("A bar item"))
    ]

router.get("/{item_id}"):
  proc read_item(item_id: int = Path()): Item =
    return Item(id: item_id, title: "Foo", price: 42.0)

router.post("/"):
  proc create_item(item: Item): Item =
    return item
