#lang pyret/library
provide *
provide-types *

import global as G
import option as O
import either as E
import equality as equality
import raw-array as RA
# import valueskeleton as VS
# valueskeleton only used on one method (_output)

include from G:
    raise,
    num-to-string as tostring,
    equal-always3,
    identical3,
    num-ceiling,
    num-max,
    num-is-integer,
end

# NOTE(alex): "include from" syntax for values NEEDS the file origin to be correct
#   if the module is a builtin module, need to indicate that (see option.arr.json for an example)
include from O:
    type Option,
    some,
    none
end

include from E:
    type Either,
    left,
    right
end

include from equality:
    within
end


# TODO(alex):
#   1) The 'list' constructor expression breaks function ordering
#      'list' constructor needs to be declared after the 'List' declarations in order
#         to have scope access to variant constructors
#      Functions declared after the 'list' constructor are no longer globally visible
#         to the code above the list constructor (no longer considered "top-level") due to being
#         after an expression which may be captured (needs to be evaluated in order)
#      Potential solutions: give constructor declarations first-class support or bite the bullet
#
#   2) Because the 'list' constructor needs to be BELOW the data declaration and it is an expression,
#      the functions that had to be moved ABOVE the 'list' constructor no longer have access to
#      the list constructor. Therefore, they need to directly use the 'list' constructor implementation.
#
#   3) Method names are allowed be shadowed and are non-recursive

# NOTE(alex): Until typechecker is updated, do NOT add type annotations to "with" methods
#   Relying on type inference in order to infer the correct refinement type
data List<a>:
  | empty with:

    method find(self, f :: (a -> Boolean)) -> Option<a>:
      doc: "Takes a predicate and returns on option containing either the first item in this list that passes the predicate, or none"
      none
    end,

    method partition(self, f :: (a -> Boolean)) -> {is-true :: List<a>, is-false :: List<a>}:
      doc: ```Takes a predicate and returns an object with two fields:
            the 'is-true' field contains the list of items in this list for which the predicate holds,
            and the 'is-false' field contains the list of items in this list for which the predicate fails```
      { is-true: empty, is-false: empty }
    end,

    method sort(self) -> List<a>:
      doc: ```Returns a new list whose contents are the smae as those in this list,
            sorted by the default ordering and equality```
      self
    end,
  | link(first :: a, rest :: List<a>) with:

    method partition(self, f :: (a -> Boolean)) -> {is-true :: List<a>, is-false :: List<a>}:
      doc: ```Takes a predicate and returns an object with two fields:
            the 'is-true' field contains the list of items in this list for which the predicate holds,
            and the 'is-false' field contains the list of items in this list for which the predicate fails```
      partition(f, self)
    end,

    method find(self, f :: (a -> Boolean)) -> Option<a>:
      doc: "Takes a predicate and returns on option containing either the first item in this list that passes the predicate, or none"
      find(f, self)
    end,

    method sort(self) -> List<a>:
      doc: ```Returns a new list whose contents are the same as those in this list,
            sorted by the default ordering and equality```
      # TODO(alex): fix ordering/sort type checking
      # self.sort-by(lam(e1,e2): e1 < e2 end, equality.within(~0))
      raise("TODO: fix typechecker / ordering to implement sort()")
    end,
sharing:
  # Note(alex): Many methods are implemented as "sharing" b/c "with" methods cannot see other "with" methods
  #   Known restriction of the typechecker (see type-checker.arr:1226)

  # method _output(self :: List<a>) -> VS.ValueSkeleton: VS.vs-collection("list", self.map(VS.vs-value)) end,

  method length(self) -> Number:
    doc: "Takes no other arguments and returns the number of links in the list"
    cases(List) self:
      | empty => 0
      | link(first, rest) => 1 + rest.length()
    end
  end,

  method member(self, elt :: a) -> Boolean:
    doc: "Returns true when the given element is equal to a member of this list"
    cases(List) self:
      | empty => false
      | link(first, rest) =>  (elt == first) or rest.member(elt)
    end
  end,

  method foldr<b>(self, f :: (a, b -> b), base :: b) -> b:
    doc: ```Takes a function and an initial value, and folds the function over this list from the right,
          starting with the initial value```
    cases(List) self:
      | empty => base
      | link(first, rest) => f(first, rest.foldr(f, base))
    end
  end,

  method foldl<b>(self, f :: (a, b -> b), base :: b) -> b:
    doc: ```Takes a function and an initial value, and folds the function over this list from the left,
          starting with the initial value```
    cases(List) self:
      | empty => base
      | link(first, rest) => rest.foldl(f, f(first, base))
    end
  end,

  method all(self, f :: (a -> Boolean)) -> Boolean:
    doc: ```Returns true if the given predicate is true for every element in this list```
    cases(List) self:
      | empty => true
      | link(first, rest) => f(first) and rest.all(f)
    end
  end,

  method any(self, f :: (a -> Boolean)) -> Boolean:
    doc: ```Returns true if the given predicate is true for any element in this list```
    cases(List) self:
      | empty => false
      | link(first, rest) =>
        f(first) or rest.any(f)
    end
  end,

  method append(self, other :: List<a>) -> List<a>:
    doc: "Takes a list and returns the result of appending the given list to this list"
    cases(List) self:
      | empty => other
      | link(first, rest) =>
        link(first, rest.append(other))
    end
  end,

  method last(self) -> a:
    doc: "Returns the last element of this list, or raises an error if the list is empty"
    cases(List) self:

      | empty =>
        raise('last: took last of empty list')

      | link(first, rest) =>
        if is-empty(rest):
          self.first
        else:
          rest.last()
        end
    end
  end,

  method sort-by(self, cmp :: (a, a -> Boolean), eq :: (a, a -> Boolean)) -> List<a> block:
    doc: ```Takes a comparator to check for elements that are strictly greater
          or less than one another, and an equality procedure for elements that are
          equal, and sorts the list accordingly.  The sort is not guaranteed to be stable.```
    cases(List) self:

      | empty => self

      | link(first, _) =>
        block:
          pivot = first
          # builds up three lists, split according to cmp and eq
          # Note: We use each, which is tail-recursive, but which causes the three
          # list parts to grow in reverse order.  This isn't a problem, since we're
          # about to sort two of those parts anyway.
          var are-lt = empty
          var are-eq = empty
          var are-gt = empty
          self.each(lam(e):
              # TODO(alex): chaining operator '^' causes a parsing error
              #if cmp(e, pivot):     are-lt := e ^ link(_, are-lt)
              #else if eq(e, pivot): are-eq := e ^ link(_, are-eq)
              #else:                 are-gt := e ^ link(_, are-gt)
              #end

              if cmp(e, pivot):     are-lt := link(e, are-lt)
              else if eq(e, pivot): are-eq := link(e, are-eq)
              else:                 are-gt := link(e, are-gt)
              end

            end)
          less :: List<a> = are-lt.sort-by(cmp, eq)
          equal :: List<a>  =  are-eq
          greater :: List<a> = are-gt.sort-by(cmp, eq)
          less.append(equal.append(greater))
        end
    end
  end,

  method _plus(self :: List<a>, other :: List<a>) -> List<a>:
    self.append(other)
  end,

  method map<b>(self, f :: (a -> b)) -> List<b>:
    doc: "Takes a function and returns a list of the result of applying that function every element in this list"
    map(f, self)
  end,

  method filter(self :: List<a>, f :: (a -> Boolean)) -> List<a>:
    doc: "Takes a predicate and returns a list containing the items in this list for which the predicate returns true."
    filter(f, self)
  end,

  method each(self :: List<a>, f :: (a -> Nothing)) -> Nothing:
    doc: "Takes a function and calls that function for each element in the list. Returns nothing"
    each(f, self)
  end,

  method reverse(self :: List<a>) -> List<a>:
    doc: "Returns a new list containing the same elements as this list, in reverse order"
    reverse(self)
  end,

  method push(self :: List<a>, elt :: a) -> List<a>:
    doc: "Adds an element to the front of the list, returning a new list"
    link(elt, self)
  end,
  method split-at(self :: List<a>, n :: Number) -> { prefix :: List<a>, suffix :: List<a> }:
    doc: "Splits this list into two lists, one containing the first n elements, and the other containing the rest"
    split-at(n, self)
  end,
  method take(self :: List<a>, n :: Number) -> List<a>:
    doc: "Returns the first n elements of this list"
    split-at(n, self).prefix
  end,
  method drop(self :: List<a>, n :: Number) -> List<a>:
    doc: "Returns all but the first n elements of this list"
    split-at(n, self).suffix
  end,

  method get(self :: List<a>, n :: Number) -> a:
    doc: "Returns the nth element of this list, or raises an error if n is out of range"
    get(self, n)
  end,
  method set(self :: List<a>, n :: Number, e :: a) -> List<a>:
    doc: "Returns a new list with the nth element set to the given value, or raises an error if n is out of range"
    function-set(self, n, e)
  end,
  method remove(self :: List<a>, e :: a) -> List<a>:
    doc: "Returns the list without the element if found, or the whole list if it is not"
    remove(self, e)
  end,
  method join-str(self :: List<a>, sep :: String) -> String:
    doc: ```Returns a string containing the tostring() forms of the elements of this list,
          joined by the provided separator string.```
    join-str(self, sep)
  end,
  method join-str-last(self :: List<a>, sep :: String, last-sep :: String) -> String:
    doc: ```Returns a string containing the tostring() forms of the elements of this list,
            joined by the provided separator string, and the provided last-separator before the last string```
    join-str-last(self, sep, last-sep)
  end,
end

fun raw-array-to-list<a>(array :: RawArray<a>) -> List<a>:
  RA.raw-array-foldr(lam(acc, current): link(current, acc) end, empty, array)
end

# TODO(alex): if performance is an issue, swap to raw JS
#   Need to pass in variant constructors explicitly b/c of runtime method construction
fun foldl-complicated<a, b>(
  is-first :: Boolean,
  flist :: List<a>,
  f :: (a, b -> b),
  x :: (a, b -> b),
  l :: (a, b -> b),
  base :: b) -> b:
  cases(List) flist:
    | link(head, tail) =>
      if is-first:
        foldl-complicated(false, tail, f, x, l, f(head, base))
      else if tail == empty:
        foldl-complicated(false, tail, f, x, l, l(head, base))
      else:
        foldl-complicated(false, tail, f, x, l, x(head, base))
      end
    | empty => base
  end
end

fun join-str<a>(l :: List<a>, sep :: String) -> String:
  f = lam(elem :: a, acc :: String):
    acc + G.js-to-string(elem)
  end

  x = lam(elem :: a, acc :: String):
    acc + sep + G.js-to-string(elem)
  end

  foldl-complicated(true, l, f, x, x, "")
where:
  # TODO(alex): unable to get type inference to see this as List<Any> instead of List<Number>
  # join-str(raw-array-to-list([RA.raw-array: 1, "2", 3]), "+") is "1+2+3"
  join-str(raw-array-to-list([RA.raw-array: 1, 2, 3]), "+") is "1+2+3"
  join-str(raw-array-to-list([RA.raw-array: ]), "+") is ""
  join-str(raw-array-to-list([RA.raw-array: 1]), "+") is "1"
  join-str(raw-array-to-list([RA.raw-array: 1, 2]), "+") is "1+2"
end

fun join-str-last<a>(jlist :: List<a>, sep :: String, last-sep :: String) -> String:
  f = lam(elem :: a, acc :: String):
    acc + G.js-to-string(elem)
  end

  x = lam(elem :: a, acc :: String):
    acc + sep + G.js-to-string(elem)
  end

  l = lam(elem :: a, acc :: String):
    acc + last-sep + G.js-to-string(elem)
  end

  foldl-complicated(true, jlist, f, x, l, "")
where:
  # TODO(alex): unable to get type inference to see this as List<Any> instead of List<Number>
  # join-str-last(raw-array-to-list([RA.raw-array: 1, "2", 3]), "+", "-") is "1+2-3"
  join-str-last(raw-array-to-list([RA.raw-array: 1, 2, 3]), "+", "-") is "1+2-3"
  join-str-last(raw-array-to-list([RA.raw-array: ]), "+", "-") is ""
  join-str-last(raw-array-to-list([RA.raw-array: 1]), "+", "-") is "1"
  join-str-last(raw-array-to-list([RA.raw-array: 1, 2]), "+", "-") is "1-2"
  join-str-last(raw-array-to-list([RA.raw-array: 1, 2, 3, 4]), "+", "-") is "1+2+3-4"
end

fun remove<a>(lst :: List<a>, elt :: a) -> List<a>:
  doc: ```Returns the list without the element if found, or the whole list if it is not```
  cases(List<a>) lst:
    | empty => empty
    | link(first, rest) =>
      if elt == lst.first:
        remove(rest, elt)
      else:
        link(first, remove(lst.rest, elt))
      end
  end
end

# TODO(alex): if performance is an issue, swap to raw JS
#   Need to pass in variant constructors explicitly b/c of runtime method construction
fun filter<a>(f :: (a -> Boolean), lst :: List<a>) -> List<a>:
  doc: "Returns the subset of lst for which f(elem) is true"
  lst.foldr(
    lam(e, acc):
      if f(e):
        link(e, acc)
      else:
        acc
      end
    end,
    empty
  )
end

fun split-at<a>(n :: Number, lst :: List<a>) -> { prefix :: List<a>, suffix :: List<a> } block:
  doc: "Splits the list into two lists, one containing the first n elements, and the other containing the rest"
  when (n < 0) or G.not(G.num-is-integer(n)):
    raise("Invalid index")
  end
  var prefix = empty
  var suffix = empty
  fun help(ind :: Number, l :: List<a>):
    if ind == 0: suffix := l
    else:
      cases(List) l block:
        | empty => raise("Index too large")
        | link(fst, rst) =>
          help(ind - 1, rst)
          prefix := fst ^ link(_, prefix)
      end
    end
  end
  help(n, lst)
  { prefix: prefix, suffix: suffix }
end

# TODO(alex): if performance is an issue, swap to raw JS
#   Need to pass in variant constructors explicitly b/c of runtime method construction
fun fold<a, b>(f :: (a, b -> a), base :: a, lst :: List<b>) -> a:
  doc: ```Takes a function, an initial value and a list, and folds the function over the list from the left,
        starting with the initial value```
  cases(List) lst:
    | link(fst, rst) =>
      fold(f, f(base, fst), rst)
    | empty =>
      base
  end
end

fun reverse<a>(lst :: List<a>) -> List<a>:
  doc: "Returns a new list containing the same elements as this list, in reverse order"
  fold(lam(acc, elt): link(elt, acc) end, empty, lst)
where:
  reverse(raw-array-to-list([RA.raw-array: ])) is raw-array-to-list([RA.raw-array: ])
  reverse(raw-array-to-list([RA.raw-array: 1, 3])) is raw-array-to-list([RA.raw-array: 3, 1])
end

fun each<a>(f :: (a -> Nothing), lst :: List<a>) -> Nothing block:
  doc: "Calls f for each elem in lst, and returns nothing"
  fold(lam(_, elt): f(elt) end, nothing, lst)
  nothing
end

# TODO(alex): if performance is an issue, swap to raw JS
#   Need to pass in variant constructors explicitly b/c of runtime method construction
fun map<a, b>(f :: (a -> b), lst :: List<a>) -> List<b> block:
  doc: "Returns a list made up of f(elem) for each elem in lst"
  cases(List) lst:
    | link(fst, rst) => link(f(fst), map(f, lst))
    | empty => empty
  end
end

fun partition<a>(f :: (a -> Boolean), lst :: List<a>) -> {is-true :: List<a>, is-false :: List<a>} block:
  doc: "Splits the list into two lists, one for which f(elem) is true, and one for which f(elem) is false"
  var is-true = empty
  var is-false = empty
  fun help(inner-lst :: List<a>):
    cases(List) inner-lst:
      | empty => nothing
      | link(first, rest) => block:
        help(rest)
        if f(inner-lst.first):
          is-true := inner-lst.first ^ link(_, is-true)
        else:
          is-false := inner-lst.first ^ link(_, is-false)
        end
        nothing
      end
    end
  end
  help(lst)
  { is-true: is-true, is-false: is-false }
end

fun find<a>(f :: (a -> Boolean), lst :: List<a>) -> Option<a>:
  doc: ```Returns some(elem) where elem is the first elem in lst for which
        f(elem) returns true, or none otherwise```

  cases(List) lst:
    | empty => none
    | link(first, rest) =>
      if f(first):
        some(first)
      else:
        find(f, rest)
      end
  end
end

fun get<a>(lst :: List<a>, n :: Number) -> a:
  doc: "Returns the nth element of the given list, or raises an error if n is out of range"
  fun help(l :: List<a>, cur :: Number):
    cases(List<a>) l:
      | empty => raise("get: n too large " + tostring(n))
      | link(first, rest) =>
      if cur == 0:
        first
      else:
        help(rest, cur - 1)
      end
    end
  end
  if n < 0: raise("get: invalid argument: " + tostring(n))
  else: help(lst, n)
  end
end

fun function-set<a>(lst :: List<a>, n :: Number, v :: a) -> List<a>:
  doc: ```Returns a new list with the same values as the given list but with the nth element
        set to the given value, or raises an error if n is out of range```
  fun help(l :: List<a>, cur :: Number):
    cases(List<a>) l:
      | empty => raise("set: n too large " + tostring(n))
      | link(first, rest) =>
        if cur == 0:
          v ^ link(_, rest)
        else:
          first ^ link(_, help(rest, cur - 1))
        end
    end
  end

  if n < 0: raise("set: invalid argument: " + tostring(n))
  else: help(lst, n)
  end
end



list = {
  make: raw-array-to-list,
  make0: lam(): empty end,
  make1: lam(a): link(a, empty) end,
  make2: lam(a, b): link(a, link(b, empty)) end,
  make3: lam(a, b, c): link(a, link(b, link(c, empty))) end,
  make4: lam(a, b, c, d): link(a, link(b, link(c, link(d, empty)))) end,
  make5: lam(a, b, c, d, e): link(a, link(b, link(c, link(d, link(e, empty))))) end,
}

fun length<a>(lst :: List<a>) -> Number:
  doc: "Takes a list and returns the number of links in the list"
  fun help(l, cur) -> Number:
    cases (List) l:
      | empty => cur
      | link(_, r) => help(r, cur + 1)
    end
  end
  help(lst, 0)
end

fun same-length<a, b>(lst1 :: List<a>, lst2 :: List<b>) -> Boolean:
  doc: "Returns true if and only if the two given lists have the same length.  Runs in time proportional to the shorter list."
  cases(List) lst1:
    | empty =>
      cases(List) lst2:
        | empty => true
        | else => false
      end
    | link(_, rest1) =>
      cases(List) lst2:
        | empty => false
        | link(_, rest2) => same-length(rest1, rest2)
      end
  end
where:
  same-length([list: 1, 2], [list: true, false]) is true
  same-length([list: 1, 2, 3], [list: true, false]) is false
  same-length([list: ], [list: true, false]) is false
end

fun longer-than<a>(lst :: List<a>, len :: Number) -> Boolean:
  doc: "Returns true if the given list is strictly longer than the given length. Runs in time proportional to the smaller of lst or len"
  cases(List) lst:
    | empty => len < 0
    | link(_, rest) => (len < 1) or longer-than(rest, len - 1)
  end
where:
  longer-than([list: 1, 2, 3], 2) is true
  longer-than([list: 1, 2, 3], 4) is false
  longer-than([list:], 0) is false
end

fun shorter-than<a>(lst :: List<a>, len :: Number) -> Boolean:
  doc: "Returns true if the given list is strictly shorter than the given length. Runs in time proportional to the smaller of lst or len"
  cases(List) lst:
    | empty => len > 0
    | link(_, rest) => (len > 1) and shorter-than(rest, len - 1)
  end
where:
  shorter-than([list: 1, 2, 3], 2) is false
  shorter-than([list: 1, 2, 3], 4) is true
  shorter-than([list:], 0) is false
end

fun push<a>(l :: List<a>, elt :: a) -> List<a>:
  link(elt, l)
end

fun last<a>(lst :: List<a>) -> a:
  doc: "Returns the last element of this list, or raises an error if the list is empty"
  fun helper(l :: List<a>) -> a:
    if is-empty(l.rest):
      l.first
    else:
      helper(l.rest)
    end
  end
  if is-empty(lst):
    raise('last: took last of empty list')
  else:
    helper(lst)
  end
end

fun sort-by<a>(lst :: List<a>, cmp :: (a, a -> Boolean), eq :: (a, a -> Boolean)) -> List<a>:
  lst.sort-by(cmp, eq)
end

fun sort<a>(lst :: List<a>) -> List<a>:
  lst.sort()
end

fun range(start :: Number, stop :: Number) -> List<Number>:
  doc: "Creates a list of numbers, starting with start, ending with stop-1"
  if start > stop: raise("range: start greater than stop: ("
        + tostring(start)
        + ", "
        + tostring(stop)
        + ")")
        else: raw-array-to-list(RA.raw-array-build(lam(i): i + start end, stop - start))
  end
end

fun range-by(start :: Number, stop :: Number, delta :: Number) -> List<Number>:
  doc: ```Creates a list of numbers, starting with start, in intervals of delta,
          until reaching (but not including) stop```
  if delta == 0:
    if start == stop: empty
    else: raise("range-by: an interval of 0 would produce an infinite list")
    end
  else:
    len = num-max(num-ceiling((stop - start) / delta), 0)
    raw-array-to-list(RA.raw-array-build(lam(i): start + (i * delta) end, len))
  end
where:
  range-by(1, 10, 4) is [list: 1, 5, 9]
  range-by(10, 1, -4) is [list: 10, 6, 2]
  range-by(3, 20, 9) is [list: 3, 12]
  range-by(20, 3, 9) is empty
  range-by(20, 3, -9) is [list: 20, 11]
  range-by(2, 3, 0) raises "interval of 0"
end

fun repeat<a>(n :: Number, e :: a) -> List<a>:
  doc: "Creates a list with n copies of e"
  if n < 0: raise("repeat: can't have a negative argument'")
  else: raw-array-to-list(RA.raw-array-of(e, n))
  end
end

fun append<a>(front :: List<a>, back :: List<a>) -> List<a>:
  cases(List<a>) front:
    | empty => back
    | link(f, r) => link(f, append(r, back))
  end
end

fun take<a>(n :: Number, lst :: List<a>) -> List<a>:
  doc: "Returns a list containing the first n elements of the given list"
  split-at(n, lst).prefix
end

fun drop<a>(n :: Number, lst :: List<a>) -> List<a>:
  doc: "Returns a list containing all but the first n elements of the given list"
  split-at(n, lst).suffix
end

fun any<a>(f :: (a -> Boolean), lst :: List<a>) -> Boolean:
  doc: "Returns true if f(elem) returns true for any elem of lst"
  if is-empty(lst):
    false
  else:
    f(lst.first) or any(f, lst.rest)
  end
end

fun all<a>(f :: (a -> Boolean), lst :: List<a>) -> Boolean:
  doc: "Returns true if f(elem) returns true for all elems of lst"
  if is-empty(lst):
    true
  else:
    f(lst.first) and all(f, lst.rest)
  end
end

fun all2<a, b>(f :: (a, b -> Boolean), lst1 :: List<b>, lst2 :: List<b>) -> Boolean:
  doc: ```Returns true if f(elem1, elem2) returns true for all corresponding elems of lst1 and list2.
        Returns true when either list is empty```
  fun help(l1, l2):
    if is-empty(l1) or is-empty(l2): true
    else: f(l1.first, l2.first) and help(l1.rest, l2.rest)
    end
  end
  help(lst1, lst2)
end

fun map2<a, b, c>(f :: (a, b -> c), l1 :: List<a>, l2 :: List<b>) -> List<c>:
  doc: "Returns a list made up of f(elem1, elem2) for each elem1 in l1, elem2 in l2"
  if is-empty(l1) or is-empty(l2):
    empty
  else:
    f(l1.first, l2.first) ^ link(_, map2(f, l1.rest, l2.rest))
  end
end

fun map3<a, b, c, d>(f :: (a, b, c -> d), l1 :: List<a>, l2 :: List<b>, l3 :: List<c>) -> List<d>:
  doc: "Returns a list made up of f(e1, e2, e3) for each e1 in l1, e2 in l2, e3 in l3"
  if is-empty(l1) or is-empty(l2) or is-empty(l3):
    empty
  else:
    f(l1.first, l2.first, l3.first) ^ link(_, map3(f, l1.rest, l2.rest, l3.rest))
  end
end

fun map4<a, b, c, d, e>(f :: (a, b, c, d -> e), l1 :: List<a>, l2 :: List<b>, l3 :: List<c>, l4 :: List<d>) -> List<e>:
  doc: "Returns a list made up of f(e1, e2, e3, e4) for each e1 in l1, e2 in l2, e3 in l3, e4 in l4"
  if is-empty(l1) or is-empty(l2) or is-empty(l3) or is-empty(l4):
    empty
  else:
    f(l1.first, l2.first, l3.first, l4.first) ^ link(_, map4(f, l1.rest, l2.rest, l3.rest, l4.rest))
  end
end

fun map_n<a, b>(f :: (Number, a -> b), n :: Number, lst :: List<a>) -> List<b>:
  doc: "Returns a list made up of f(n, e1), f(n+1, e2) .. for e1, e2 ... in lst"
  if is-empty(lst):
    empty
  else:
    f(n, lst.first) ^ link(_, map_n(f, n + 1, lst.rest))
  end
end

fun map2_n<a, b, c>(f :: (Number, a, b -> c), n :: Number, l1 :: List<a>, l2 :: List<b>) -> List<c>:
  doc: "Returns a list made up of f(i, e1, e2) for each e1 in l1, e2 in l2, and i counting up from n"
  if is-empty(l1) or is-empty(l2):
    empty
  else:
    f(n, l1.first, l2.first) ^ link(_, map2_n(f, n + 1, l1.rest, l2.rest))
  end
end

fun map3_n<a, b, c, d>(f :: (Number, a, b, c -> d), n :: Number, l1 :: List<a>, l2 :: List<b>, l3 :: List<c>) -> List<d>:
  doc: "Returns a list made up of f(i, e1, e2, e3) for each e1 in l1, e2 in l2, e3 in l3, and i counting up from n"
  if is-empty(l1) or is-empty(l2) or is-empty(l3):
    empty
  else:
    f(n, l1.first, l2.first, l3.first) ^ link(_, map3_n(f, n + 1, l1.rest, l2.rest, l3.rest))
  end
end

fun map4_n<a, b, c, d, e>(f :: (Number, a, b, c, d -> e), n :: Number, l1 :: List<a>, l2 :: List<b>, l3 :: List<c>, l4 :: List<d>) -> List<e>:
  doc: "Returns a list made up of f(i, e1, e2, e3, e4) for each e1 in l1, e2 in l2, e3 in l3, e4 in l4, and i counting up from n"
  if is-empty(l1) or is-empty(l2) or is-empty(l3) or is-empty(l4):
    empty
  else:
    f(n, l1.first, l2.first, l3.first, l4.first) ^ link(_, map4_n(f, n + 1, l1.rest, l2.rest, l3.rest, l4.rest))
  end
end

fun each2<a, b>(f :: (a, b -> Nothing), lst1 :: List<a>, lst2 :: List<b>) -> Nothing:
  doc: "Calls f on each pair of corresponding elements in l1 and l2, and returns nothing.  Stops after the shortest list"
  fun help(l1, l2):
    if is-empty(l1) or is-empty(l2) block:
      nothing
    else:
      f(l1.first, l2.first)
      help(l1.rest, l2.rest)
    end
  end
  help(lst1, lst2)
end

fun each3<a, b, c>(f :: (a, b, c -> Nothing), lst1 :: List<a>, lst2 :: List<b>, lst3 :: List<c>) -> Nothing:
  doc: "Calls f on each triple of corresponding elements in l1, l2 and l3, and returns nothing.  Stops after the shortest list"
  fun help(l1, l2, l3):
    if is-empty(l1) or is-empty(l2) or is-empty(l3) block:
      nothing
    else:
      f(l1.first, l2.first, l3.first)
      help(l1.rest, l2.rest, l3.rest)
    end
  end
  help(lst1, lst2, lst3)
end

fun each4<a, b, c, d>(f :: (a, b, c, d -> Nothing), lst1 :: List<a>, lst2 :: List<b>, lst3 :: List<c>, lst4 :: List<d>):
  doc: "Calls f on each tuple of corresponding elements in l1, l2, l3 and l4, and returns nothing.  Stops after the shortest list"
  fun help(l1, l2, l3, l4):
    if is-empty(l1) or is-empty(l2) or is-empty(l3) or is-empty(l4) block:
      nothing
    else:
      f(l1.first, l2.first, l3.first, l4.first)
      help(l1.rest, l2.rest, l3.rest, l4.rest)
    end
  end
  help(lst1, lst2, lst3, lst4)
end

fun each_n<a>(f :: (Number, a -> Nothing), num :: Number, lst:: List<a>) -> Nothing:
  doc: "Calls f(i, e) for each e in lst and with i counting up from num, and returns nothing"
  fun help(n, l):
    if is-empty(l) block:
      nothing
    else:
      f(n, l.first)
      help(n + 1, l.rest)
    end
  end
  help(num, lst)
end

fun each2_n<a, b>(f :: (Number, a, b -> Nothing), num :: Number, lst1 :: List<a>, lst2 :: List<b>) -> Nothing:
  doc: "Calls f(i, e1, e2) for each e1 in lst1, e2 in lst2 and with i counting up from num, and returns nothing"
  fun help(n, l1, l2):
    if is-empty(l1) or is-empty(l2) block:
      nothing
    else:
      f(n, l1.first, l2.first)
      help(n + 1, l1.rest, l2.rest)
    end
  end
  help(num, lst1, lst2)
end

fun each3_n<a, b, c>(f :: (Number, a, b, c -> Nothing), num :: Number, lst1 :: List<a>, lst2 :: List<b>, lst3 :: List<c>) -> Nothing:
  doc: "Calls f(i, e1, e2, e3) for each e1 in lst1, e2 in lst2, e3 in lst3 and with i counting up from num, and returns nothing"
  fun help(n, l1, l2, l3):
    if is-empty(l1) or is-empty(l2) or is-empty(l3) block:
      nothing
    else:
      f(n, l1.first, l2.first, l3.first)
      help(n + 1, l1.rest, l2.rest, l3.rest)
    end
  end
  help(num, lst1, lst2, lst3)
end

fun each4_n<a, b, c, d>(f :: (a, b, c, d -> Nothing), num :: Number, lst1 :: List<a>, lst2 :: List<b>, lst3 :: List<c>, lst4 :: List<d>) -> Nothing:
  doc: "Calls f(i, e1, e2, e3, e4) for each e1 in lst1, e2 in lst2, e3 in lst3, e4 in lst4 and with i counting up from num, and returns nothing"
  fun help(n, l1, l2, l3, l4):
    if is-empty(l1) or is-empty(l2) or is-empty(l3) or is-empty(l4) block:
      nothing
    else:
      f(n, l1.first, l2.first, l3.first, l4.first)
      help(n + 1, l1.rest, l2.rest, l3.rest, l4.rest)
    end
  end
  help(num, lst1, lst2, lst3, lst4)
end

fun fold-while<a, b>(f :: (a, b -> Either<a, a>), base :: a, lst :: List<b>) -> a:
  doc: ```Takes a function that takes two arguments and returns an Either, and also a base value, and folds
        over the given list from the left as long as the function returns a left() value, and returns either
        the final value or the right() value```
  cases(List) lst:
    | empty => base
    | link(elt, r) =>
      cases(Either) f(base, elt):
        | left(v) => fold-while(f, v, r)
        | right(v) => v
      end
  end
end

fun foldr<a, b>(f :: (a, b -> a), base :: a, lst :: List<b>) -> a:
  doc: ```Takes a function, an initial value and a list, and folds the function over the list from the right,
        starting with the initial value```
  if is-empty(lst):
    base
  else:
    f(foldr(f, base, lst.rest), lst.first)
  end
end

fun fold2<a, b, c>(f :: (a, b, c -> a), base :: a, l1 :: List<b>, l2 :: List<c>) -> a:
  doc: ```Takes a function, an initial value and two lists, and folds the function over the lists in parallel
        from the left, starting with the initial value and ending when either list is empty```
  if is-empty(l1) or is-empty(l2):
    base
  else:
    fold2(f, f(base, l1.first, l2.first), l1.rest, l2.rest)
  end
end

fun fold3<a, b, c, d>(f :: (a, b, c, d -> a), base :: a, l1 :: List<b>, l2 :: List<c>, l3 :: List<d>) -> a:
  doc: ```Takes a function, an initial value and three lists, and folds the function over the lists in parallel
        from the left, starting with the initial value and ending when any list is empty```
  if is-empty(l1) or is-empty(l2) or is-empty(l3):
    base
  else:
    fold3(f, f(base, l1.first, l2.first, l3.first), l1.rest, l2.rest, l3.rest)
  end
end

fun fold4<a, b, c, d, e>(f :: (a, b, c, d, e -> a), base :: a, l1 :: List<b>, l2 :: List<c>, l3 :: List<d>, l4 :: List<e>) -> a:
  doc: ```Takes a function, an initial value and four lists, and folds the function over the lists in parallel
        from the left, starting with the initial value and ending when any list is empty```
  if is-empty(l1) or is-empty(l2) or is-empty(l3) or is-empty(l4):
    base
  else:
    fold4(f, f(base, l1.first, l2.first, l3.first, l4.first), l1.rest, l2.rest, l3.rest, l4.rest)
  end
end

fun fold_n<a, b>(f :: (Number, a, b -> a), num :: Number, base :: a, lst :: List<b>) -> a:
  doc: ```Takes a function, an initial value and a list, and folds the function over the list from the left,
        starting with the initial value and passing along the index (starting with the given num)```
  fun help(n, acc, partial-list):
    if is-empty(partial-list):
      acc
    else:
      help(n + 1, f(n, acc, partial-list.first), partial-list.rest)
    end
  end
  help(num, base, lst)
end

fun member-with<a>(lst :: List<a>, elt :: a, eq :: (a, a -> equality.EqualityResult)):
  ask:
    | is-empty(lst) then: equality.NotEqual("list", elt, lst)
    | is-link(lst) then:
      f = lst.first
      r = lst.rest
      first-elt-equal = eq(f, elt)
      cases(equality.EqualityResult) first-elt-equal:
        | Equal => equality.Equal
        | else => equality.equal-or(first-elt-equal, member-with(r, elt, eq))
      end
  end
end

fun member3<a>(lst :: List<a>, elt :: a) -> equality.EqualityResult:
  member-with(lst, elt, equal-always3)
end

fun member<a>(lst :: List<a>, elt :: a) -> Boolean:
  equality.to-boolean(member3(lst, elt))
end

fun member-now3<a>(lst :: List<a>, elt :: a) -> equality.EqualityResult:
  member-with(lst, elt, equality.equal-now3)
end

fun member-now<a>(lst :: List<a>, elt :: a) -> Boolean:
  equality.to-boolean(member-now3(lst, elt))
end

fun member-identical3<a>(lst :: List<a>, elt :: a) -> equality.EqualityResult:
  member-with(lst, elt, identical3)
end

fun member-identical<a>(lst :: List<a>, elt :: a) -> Boolean:
  equality.to-boolean(member-identical3(lst, elt))
end

fun shuffle<a>(lst :: List<a>) -> List<a>:
  if is-empty(lst): empty
  else:
    elts = for fold_n(i from 1, arr from RA.raw-array-of(lst.first, lst.length()), e from lst.rest) block:
      # TODO(alex): implement random somewhere
      # ix = random(i + 1)
      ix = raise("TODO(alex): Implement random generator somewhere")
      RA.raw-array-set(arr, i, RA.raw-array-get(arr, ix))
      RA.raw-array-set(arr, ix, e)
      arr
    end
    raw-array-to-list(elts)
  end
end

fun filter-map<a, b>(f :: (a -> Option<b>), lst :: List<a>) -> List<b>:
  cases(List<a>) lst:
    | empty => empty
    | link(first, rest) =>
      cases(Option<b>) f(first):
        | none => filter-map(f, rest)
        | some(v) => link(v, filter-map(f, rest))
      end
  end
end

fun filter-values<a>(lst :: List<Option<a>>) -> List<a>:
  cases(List<a>) lst:
    | empty => empty
    | link(first, rest) =>
      cases(Option<a>) first:
        | none => filter-values(rest)
        | some(v) => link(v, filter-values(rest))
      end
  end
end

fun distinct<A>(l :: List<A>) -> List<A>:
  doc: "returns a list with exactly the distinct elements of the original list removing the first instance"
  cases (List) l:
    | empty => empty
    | link(first, rest) =>
      cases(equality.EqualityResult) member3(rest, first):
        | NotEqual(_, _, _) => link(first, distinct(rest))
        | Unknown(_, _, _) => link(first, distinct(rest))
        | Equal => distinct(rest)
      end
  end
end

fun take-while<A>(pred :: (A -> Boolean), lst :: List<A>) -> {List<A>; List<A>}:
  doc: "Splits a list into two pieces, at the first element that fails the given predicate"
  var tail = empty
  fun help(l):
    cases(List) l:
      | empty => empty
      | link(first, rest) =>
        if pred(first) block:
          link(first, help(rest))
        else:
          tail := l
          empty
        end
    end
  end
  { help(lst); tail }
where:
  # TODO(alex): binop currying results in an error (underscore-as-expr)
  #   from resolve-scope.arr:check-unbound-ids-bad-assignments()
  #   Ex: _ > 0
  #
  take-while(lam(x): x > 0 end, [list: 5, 3, 1, 0, 1, 2, 3]) is { [list: 5, 3, 1]; [list: 0, 1, 2, 3] }
  take-while(lam(x): x > 0 end, empty) is { empty; empty }
  take-while(lam(x): x > 0 end, [list: 0, 1, 2, 3]) is { empty; [list: 0, 1, 2, 3] }
  take-while(lam(x): x > 0 end, [list: 5, 4, 3, 2, 1]) is { [list: 5, 4, 3, 2, 1]; empty }
  take-while(lam(x): x == true end, [list: true, true, false, true]) is { [list: true, true]; [list: false, true] }
end

member-always3 = member3
member-always = member
foldl = fold