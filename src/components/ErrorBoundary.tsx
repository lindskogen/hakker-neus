import * as React from "react";
import { Component, ErrorInfo, ReactNode } from "react";

interface Props {
  fallback: ReactNode;
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
    this.setState({ error });
  }

  render() {
    const { children, fallback } = this.props;
    const { error } = this.state;

    if (error !== null) {
      return fallback;
    }

    return children;
  }
}
