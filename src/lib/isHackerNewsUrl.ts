export const isHackerNewsUrl = (href: string): boolean =>
  /^https?:\/\/news.ycombinator.com/.test(href);
