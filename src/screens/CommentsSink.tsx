import * as React from "react";
import { ScrollView, Text } from "react-native";
import HTML from "react-native-render-html";
import { NavigationScreenProp } from "react-navigation";
import { CommentWithChildren } from "../components/CommentWithChildren";

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

const linkComment = `&gt;&gt; they seem ... incompatible with such performance<p>Might answer your question [0]<p>[0] <a href=\"https:&#x2F;&#x2F;news.ycombinator.com&#x2F;item?id=2192629\" rel=\"nofollow\">https:&#x2F;&#x2F;news.ycombinator.com&#x2F;item?id=2192629</a>`;

const multipleCodeComment = `Failed entirely to work on my first attempt with:<p><pre><code>    curl -XHEAD https:&#x2F;&#x2F;google.com\n</code></pre>\nIt is just flat out wrong on:<p><pre><code>    curl -X HEAD https:&#x2F;&#x2F;google.com\n</code></pre>\nIn that it does a GET request:<p><pre><code>    import requests\n    \n    response = requests.get(&#x27;https:&#x2F;&#x2F;google.com&#x2F;&#x27;)\n</code></pre>\nClever idea, but my first totally valid example failed (it does OPTIONS, GET, POST, PUT, PATCH successfully)`;

export const CommentsSink: React.FC<{
  navigation: NavigationScreenProp<{}, {}>;
}> = ({ navigation }) => {
  const text = linkComment;

  return (
    <ScrollView style={{ flex: 1 }}>
      <CommentWithChildren
        op={'testing'}
        comment={{
          id: 234,
          type: "comment",
          text: text,
          by: { id: "testing" },
          kids: [],
          timeISO: new Date().toISOString()
        }}
        depth={0}
        navigation={navigation}
      />
      <Text style={{ color: "black" }}>{text}</Text>
      <HTML html={text} />
    </ScrollView>
  );
};
