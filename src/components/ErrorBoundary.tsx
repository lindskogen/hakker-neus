import * as React from "react";
import { Component, ErrorInfo, ReactNode } from "react";
import { bugsnag } from "../lib/error-tracking";

interface Props {
  fallback: ReactNode | ((error: Error) => ReactNode);
  onError?: (error: Error, componentStack: string) => void;
}

interface State {
  error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = {
    error: null
  };

  componentDidCatch(error: Error, info: ErrorInfo): void {
    bugsnag.notify(error, report => {
      if (info && info.componentStack) {
        report.addMetadata(
          "react",
          "componentStack",
          formatComponentStack(info.componentStack)
        );
      }
    });

    this.setState({ error });
  }

  render() {
    const { children, fallback } = this.props;
    const { error } = this.state;

    if (error !== null) {
      return typeof fallback === "function" ? fallback(error) : fallback;
    }

    return children;
  }
}

const formatComponentStack = (str: string): string => {
  const lines = str.split(/\s*\n\s*/g);
  let ret = "";
  for (let line = 0, len = lines.length; line < len; line++) {
    if (lines[line].length) ret += `${ret.length ? "\n" : ""}${lines[line]}`;
  }
  return ret;
};
