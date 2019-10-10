import { AllHtmlEntities } from "html-entities";
import qs from "query-string";
import * as React from "react";
import { ScrollView, Text } from "react-native";

const entities = new AllHtmlEntities();

interface IDoc {
  type: string;
  content?: string;
  voidElement: boolean;
  name: string;
  attrs: {};
  children: IDoc[];
}

export function formatTag(
  navigation: any,
  tag: IDoc,
  index: number,
  fontFamily: string = "Helvetica Neue"
): React.ReactElement {
  if (tag.type === "text") {
    return (
      <Text
        key={index}
        style={{
          fontSize: 16,
          fontFamily,
          color: "white"
        }}
      >
        {entities.decode(tag.content)}
      </Text>
    );
  } else if (tag.name === "p") {
    return (
      <Text key={index} style={{ marginTop: 10 }}>
        {tag.children.map((childTag, i) =>
          formatTag(navigation, childTag, i, fontFamily)
        )}
      </Text>
    );
  } else if (tag.name === "a") {
    return (
      <Text
        key={index}
        style={{ textDecorationLine: "underline" }}
        onPress={() => {
          const href = entities.decode(tag.attrs.href);
          if (/^https?:\/\/news.ycombinator.com/.test(href)) {
            const parsedHref = qs.parseUrl(href);
            const { id } = parsedHref.query;
            navigation.navigate({
              routeName: "Comments",
              params: { id }
            });
          } else {
            navigation.navigate({
              routeName: "Browser",
              params: { url: href }
            });
          }
        }}
      >
        {tag.children.map((childTag, i) =>
          formatTag(navigation, childTag, i, fontFamily)
        )}
      </Text>
    );
  } else if (tag.name === "i") {
    return (
      <Text key={index} style={{ fontStyle: "italic" }}>
        {tag.children.map((childTag, i) => formatTag(navigation, childTag, i))}
      </Text>
    );
  } else if (
    tag.name === "pre" &&
    tag.children.length === 1 &&
    tag.children[0].name === "code"
  ) {
    return (
      <ScrollView key={index} horizontal={true}>
        {tag.children[0].children.map((childTag, i) =>
          formatTag(navigation, childTag, i, "Menlo")
        )}
      </ScrollView>
    );
  } else {
    return <Text>{JSON.stringify(tag)}</Text>;
  }
}
