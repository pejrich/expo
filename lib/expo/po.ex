defmodule Expo.PO do
  @moduledoc """
  File handling for PO (`.po`) and POT (`.pot`) files.
  """

  alias Expo.Messages
  alias Expo.PO.{DuplicateMessagesError, Parser, SyntaxError}

  @type parse_options :: [{:file, Path.t()}]

  @type parse_error :: {:error, {:parse_error, message :: String.t(), line :: pos_integer()}}
  @type duplicate_messages_error ::
          {:error,
           {:duplicate_messages,
            [{message :: String.t(), new_line :: pos_integer(), old_line :: pos_integer()}]}}
  @type file_error :: {:error, File.posix()}

  @doc """
  Dumps a `Expo.Messages` struct as iodata.

  This function dumps a `Expo.Messages` struct (representing a PO file) as iodata,
  which can later be written to a file or converted to a string with
  `IO.iodata_to_binary/1`.

  ## Examples

  After running the following code:

      iodata =
        Expo.PO.compose(%Expo.Messages{
          headers: ["Last-Translator: Jane Doe"],
          messages: [
            %Expo.Message.Singular{msgid: ["foo"], msgstr: ["bar"], comments: "A comment"}
          ]
        })

      File.write!("/tmp/test.po", iodata)

  the `/tmp/test.po` file would look like this:

      msgid ""
      msgstr ""
      "Last-Translator: Jane Doe"

      # A comment
      msgid "foo"
      msgstr "bar"

  """
  @spec compose(Messages.t()) :: iodata()
  defdelegate compose(messages), to: Expo.PO.Composer

  @doc """
  Parses the ginve `string` into a `Expo.Messages` struct.

  It returns `{:ok, messages}` if there are no errors,
  otherwise `{:error, line, reason}`.

  ## Examples

      iex> {:ok, po} = Expo.PO.parse_string(\"""
      ...> msgid "foo"
      ...> msgstr "bar"
      ...> \""")
      iex> [message] = po.messages
      iex> message.msgid
      ["foo"]
      iex> message.msgstr
      ["bar"]
      iex> po.headers
      []

      iex> Expo.PO.parse_string("foo")
      {:error, {:parse_error, "unknown keyword 'foo'", 1}}

  """
  @spec parse_string(String.t(), parse_options()) ::
          {:ok, Messages.t()}
          | parse_error()
          | duplicate_messages_error()
  def parse_string(string, options \\ []) do
    Parser.parse(string, options)
  end

  @doc """
  Parses `string` into a `Expo.Messages` struct, raising an exception if there are
  any errors.

  Works exactly like `parse_string/1`, but returns a `Expo.Messages` struct
  if there are no errors or raises an exception if there are.

  ## Examples

      iex> po = Expo.PO.parse_string!(\"""
      ...> msgid "foo"
      ...> msgstr "bar"
      ...> \""")
      iex> [message] = po.messages
      iex> message.msgid
      ["foo"]
      iex> message.msgstr
      ["bar"]
      iex> po.headers
      []

      iex> Expo.PO.parse_string!("msgid")
      ** (Expo.PO.SyntaxError) 1: no space after 'msgid'

      iex> Expo.PO.parse_string!(\"""
      ...> msgid "test"
      ...> msgstr ""
      ...>
      ...> msgid "test"
      ...> msgstr ""
      ...> \""")
      ** (Expo.PO.DuplicateMessagesError) 4: found duplicate on line 4 for msgid: 'test'

  """
  @spec parse_string!(String.t(), parse_options()) :: Messages.t()
  def parse_string!(string, opts \\ []) do
    case parse_string(string, opts) do
      {:ok, parsed} ->
        parsed

      {:error, {:parse_error, reason, line}} ->
        options = [line: line, reason: reason]

        options =
          case opts[:file] do
            nil -> options
            path -> [{:file, path} | options]
          end

        raise SyntaxError, options

      {:error, {:duplicate_messages, duplicates}} ->
        options = [duplicates: duplicates]

        options =
          case opts[:file] do
            nil -> options
            path -> [{:file, path} | options]
          end

        raise DuplicateMessagesError, options
    end
  end

  @doc """
  Parses the contents of a file into a `Expo.Messages` struct.

  This function works similarly to `parse_string/1` except that it takes a file
  and parses the contents of that file. It can return:

    * `{:ok, po}` if the parsing is successful

    * `{:error, line, reason}` if there is an error with the contents of the
      `.po` file (for example, a syntax error)

    * `{:error, reason}` if there is an error with reading the file (this error
      is one of the errors that can be returned by `File.read/1`)

  ## Examples

      {:ok, po} = Expo.PO.parse_file("messages.po")
      po.file
      #=> "messages.po"

      Expo.PO.parse_file("nonexistent")
      #=> {:error, :enoent}

  """
  @spec parse_file(Path.t(), parse_options()) ::
          {:ok, Messages.t()}
          | parse_error()
          | duplicate_messages_error()
          | file_error()
  def parse_file(path, options \\ []) when is_list(options) do
    with {:ok, contents} <- File.read(path) do
      parse_string(contents, Keyword.put_new(options, :file, path))
    end
  end

  @doc """
  Parses the contents of a file into a `Expo.Messages` struct, raising if there
  are any errors.

  Works like `parse_file/1`, except that it raises an exception
  if there are issues with the contents of the file or with reading the file.

  ## Examples

      Expo.PO.parse_file!("nonexistent.po")
      #=> ** (File.Error) could not parse "nonexistent.po": no such file or directory

  """
  @spec parse_file!(Path.t(), parse_options()) :: Messages.t()
  def parse_file!(path, opts \\ []) do
    case parse_file(path, opts) do
      {:ok, parsed} ->
        parsed

      {:error, {:parse_error, reason, line}} ->
        raise SyntaxError, line: line, reason: reason, file: path

      {:error, {:duplicate_messages, duplicates}} ->
        raise DuplicateMessagesError,
          duplicates: duplicates,
          file: Keyword.get(opts, :file, path)

      {:error, reason} ->
        raise File.Error, reason: reason, action: "parse", path: Keyword.get(opts, :file, path)
    end
  end
end
