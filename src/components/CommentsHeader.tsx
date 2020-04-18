import { parseISO } from "date-fns";
import * as React from "react";
import { Text, View } from "react-native";
import { HNComment } from "../common/types";
import { fontFamily, padding } from "../common/vars";
import { RelativeTime } from "../common/CurrentTimeContext";

export const CommentHeader = ({
  comment,
  isOp
}: {
  isOp: boolean;
  comment: HNComment;
}) => (
  <View
    style={{
      flexDirection: "row",
      justifyContent: "space-between",
      alignItems: "center",
      paddingBottom: padding
    }}
  >
    <View
      style={{
        flexDirection: "row",
        alignItems: "center"
      }}
    >
      <Text
        style={{
          fontSize: 13,
          fontFamily,
          fontWeight: '500',
          color: "white"
        }}
      >
        {comment.by?.id ?? 'deleted'}
      </Text>
      {isOp && (
        <View
          style={{
            borderRadius: 3,
            padding: 2,
            marginLeft: 5,
            justifyContent: "center",
            alignItems: "center",
            backgroundColor: "#fff2"
          }}
        >
          <Text
            style={{
              fontSize: 8,
              fontFamily,
              color: "white",
              textTransform: "uppercase",
              fontWeight: "bold"
            }}
          >
            OP
          </Text>
        </View>
      )}
    </View>
    <Text
      style={{
        fontSize: 13,
        fontFamily,
        color: "white"
      }}
    >
      <RelativeTime pastDate={parseISO(comment.timeISO)} />
    </Text>
  </View>
);
