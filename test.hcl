target "app" {
  name = "app-${item[0]}-${item[1]}"
  matrix = {
    item = setproduct(["a", "b"], ["1", "2"])
  }
}
