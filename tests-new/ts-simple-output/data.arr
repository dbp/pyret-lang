### 2
include global
data L:
  | mt(f :: Number) with:
    method len(self): self.base() end
  | lunk(f :: Number, r :: L) with:
    method len(self): 1 + self.r.len() end
sharing:
  method len(self): raise("oops") end,
  method base(self):
    0
  end
end
l = lunk(5, lunk(9, mt(10)))
console-log(l.len())
console-log(is-lunk(l))
console-log(is-mt(mt(777777)))
console-log(is-lunk(mt(8)))