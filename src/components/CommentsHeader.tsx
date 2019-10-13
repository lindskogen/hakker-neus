import { formatDistanceStrict, parseISO } from "date-fns";
import * as React from "react";
import { Text, View } from "react-native";
import { HNComment } from "../common/types";
import { padding } from "../common/vars";

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
          fontSize: 10,
          fontFamily: "Helvetica Neue",
          color: "white",
          textTransform: "uppercase"
        }}
      >
        {comment.by.id}
      </Text>
      {isOp && (
        <View
          style={{
            borderRadius: 3,
            padding: 2,
            marginLeft: 5,
            justifyContent: "center",
            alignItems: "center",
            backgroundColor: "rgba(0, 0, 0, 0.1)"
          }}
        >
          <Text
            style={{
              fontSize: 8,
              fontFamily: "Helvetica Neue",
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
        fontSize: 10,
        fontFamily: "Helvetica Neue",
        color: "white"
      }}
    >
      {formatDistanceStrict(parseISO(comment.timeISO), new Date())}
    </Text>
  </View>
);
