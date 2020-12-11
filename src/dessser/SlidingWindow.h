#ifndef SIMPLESET_H_201202
#define SIMPLESET_H_201202
#include "dessser/Set.h"

template<class T>
struct SlidingWindow : public Set<T> {
  /* From oldest to youngest: */
  std::list<T> l;

  SlidingWindow() {}
  SlidingWindow(SlidingWindow const &other) : l(other.l) {}
  ~SlidingWindow() {}

  void insert(T const &x) override {
    l.push_back(x);
  }

  std::pair<T, std::list<T>> lastUpdate() const override {
    return std::pair<T, std::list<T>>(
      l.back(), std::list<T>());
  }

  uint32_t size() const override {
    return l.size();
  }

  typename std::list<T>::iterator begin() { return l.begin(); }
  typename std::list<T>::iterator end() { return l.end(); }
};

#endif