import * as d3 from "d3-scale-chromatic";
import { formatDistanceStrict, parseISO } from "date-fns";
import HTML  from "html-parse-stringify";
import * as React from "react";
import { StyleSheet, Text, TouchableOpacity, View } from "react-native";
import { IDoc } from "../common/types";
import { padding } from "../common/vars";
import { formatTag } from "../html/formatTag";


export function parseHTML(comment: string): IDoc {
  const astRoot: IDoc[] = HTML.parse(comment);
  return astRoot[0];
}

export function formatHTMLContent(comment: string, navigation) {
  const astRoot = parseHTML("<div>" + comment + "</div>");
  return <View>{astRoot.children.map((tag, index) => formatTag(navigation, tag, index))}</View>;
}

export const CommentWithChildren = ({
  comment,
  depth,
                                      navigation
}: {
  comment: ItemT;
  depth: number;
}) => (
  <View
    style={{
      marginTop: depth === 0 ? 0 : padding,
      marginLeft: (padding / 2) * depth,
      minHeight: 40,
      backgroundColor: d3.interpolateBlues(0.6)
    }}
  >
    <View
      style={{
        padding,
        paddingVertical: padding / 2,
        borderLeftColor:
          depth === 0 ? "transparent" : d3.schemeTableau10[depth],
        borderLeftWidth: 5
      }}
    >
      <View
        style={{
          flexDirection: "row",
          justifyContent: "space-between",
          paddingBottom: padding
        }}
      >
        <Text
          style={{
            fontSize: 10,

            fontFamily: "Helvetica Neue",
            color: "white",
            textTransform: "uppercase"
          }}
        >
          {comment.by.id}
        </Text>
        <Text
          style={{
            fontSize: 10,
            fontFamily: "Helvetica Neue",
            color: "white"
          }}
        >
          {formatDistanceStrict(parseISO(comment.timeISO), new Date())}
        </Text>
      </View>
      <TouchableOpacity
        onPress={() => console.log(comment.text, parseHTML(comment.text))}
      >
        {formatHTMLContent(comment.text, navigation)}
      </TouchableOpacity>
    </View>
    {(comment.kids || [])
      .filter(kid => !!kid.text)
      .map(kid => (
        <CommentWithChildren key={kid.id} comment={kid} depth={depth + 1} />
      ))}
  </View>
);
