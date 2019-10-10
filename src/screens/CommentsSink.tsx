import * as React from "react";
import { ScrollView, Text } from "react-native";
import {
  CommentWithChildren, formatHTMLContent,
  parseHTML
} from "../components/CommentWithChildren";
import { formatTag } from "../html/formatTag";

const codeComment = `Actually, that&#x27;s right, forgot about that :P<p>The only remaining mystery then would be why they bothered encoding it like this:<p><pre><code>    0xxxxxxx
    110xxxxx  10xxxxxx        
    1110xxxx  10xxxxxx  10xxxxxx    
    11110xxx  10xxxxxx  10xxxxxx  10xxxxxx
</code></pre>
... when it could have been done much more simply by putting the continuation bit in position 6 and keeping bit 7 set across the entire multibyte sequence:<p><pre><code>    0xxxxxxx
    11xxxxxx  11xxxxxx  ...  10xxxxxx
</code></pre>
Or even like this for maximum compactness:<p><pre><code>    0xxxxxxx
    100xxxxx 1xxxxxxx
    101xxxxx 1xxxxxxx 1xxxxxxx
    110xxxxx 1xxxxxxx 1xxxxxxx 1xxxxxxx
    111xxxxx 1xxxxxxx 1xxxxxxx 1xxxxxxx 1xxxxxxx</code></pre>`;

const linkComment = `Intel and AMD CPUs do not share a common socket (or chipset) on server, desktop, or mobile platforms. I think the last shared socket was Socket 7 [0], released back in 1995.<p>0: <a href="https:&#x2F;&#x2F;en.wikipedia.org&#x2F;wiki&#x2F;Socket_7" rel="nofollow">https:&#x2F;&#x2F;en.wikipedia.org&#x2F;wiki&#x2F;Socket_7</a>`

export const CommentsSink = () => {
  const text = linkComment;
  console.log(formatHTMLContent(text));

  return (
    <ScrollView style={{ flex: 1 }}>
      <CommentWithChildren
        comment={{ text: text, by: { id: "testing" }, kids: [], timeISO: new Date().toISOString() }}
        depth={0}
      />
      <Text style={{ color: "black" }}>{text}</Text>
      <Text style={{ color: "black" }}>
        {JSON.stringify(parseHTML(text).children, null, 2)}
      </Text>
    </ScrollView>
  );
};
